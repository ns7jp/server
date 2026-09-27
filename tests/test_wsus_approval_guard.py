"""Execute the documented WSUS approval block with an in-memory API double.

No WSUS connection, update approval, download, or VM operation is performed.
"""

import json
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")

HARNESS = r'''
param([string]$Scenario, [string]$Document)
$ErrorActionPreference = 'Stop'
Add-Type @'
namespace Microsoft.UpdateServices.Administration {
    public enum ApprovedStates { Any }
    public class UpdateScope {
        public System.Collections.ArrayList Classifications = new System.Collections.ArrayList();
        public System.Collections.ArrayList Categories = new System.Collections.ArrayList();
        public ApprovedStates ApprovedStates;
    }
}
'@
$script:scenario = $Scenario
$script:persistedEnabled = $false
$script:applyCalls = 0
$script:disableAttempts = 0

function New-MockRule {
    $rule = [pscustomobject]@{
        Name = 'Critical and Security Updates - Pilot Auto-Approve'
        Enabled = $script:persistedEnabled
    }
    $rule | Add-Member ScriptMethod GetUpdateClassifications {
        if ($script:scenario -eq 'empty-filter') { return }
        [pscustomobject]@{ Title = 'Security' }
    }
    $rule | Add-Member ScriptMethod GetCategories {
        [pscustomobject]@{ Title = 'Server' }
    }
    $rule | Add-Member ScriptMethod GetComputerTargetGroups {
        [pscustomobject]@{ Name = 'Pilot' }
    }
    $rule | Add-Member ScriptMethod Save {
        if ($this.Enabled) {
            # A failed response need not mean that the server did not save.
            $script:persistedEnabled = $true
            if ($script:scenario -eq 'enable-save-fails') { throw 'ENABLE_SAVE_FAILED' }
        }
        else {
            $script:disableAttempts++
            if ($script:scenario -in @('cleanup-fails', 'both-fail')) {
                throw 'DISABLE_SAVE_FAILED'
            }
            if ($script:scenario -ne 'readback-enabled') {
                $script:persistedEnabled = $false
            }
        }
    }
    $rule | Add-Member ScriptMethod ApplyRule {
        $script:applyCalls++
        if ($script:scenario -in @('apply-fails', 'both-fail')) { throw 'APPLY_FAILED' }
        'update-1', 'update-2'
    }
    $rule
}

$wsus = [pscustomobject]@{}
$wsus | Add-Member ScriptMethod GetInstallApprovalRules {
    if ($script:scenario -eq 'missing-rule') { return }
    New-MockRule
    if ($script:scenario -eq 'duplicate-rule') { New-MockRule }
}
$wsus | Add-Member ScriptMethod GetUpdates { 'update-1', 'update-2' }
$wsus | Add-Member ScriptMethod GetStatus { [pscustomobject]@{ UpdateCount = 10 } }

$documentText = Get-Content -Raw -LiteralPath $Document -Encoding utf8
$match = [regex]::Match($documentText, '(?s)### 9\.2 .*?```powershell\r?\n(.*?)```')
if (-not $match.Success) { throw 'APPROVAL_BLOCK_NOT_FOUND' }
$block = [scriptblock]::Create($match.Groups[1].Value)
$failure = $null
$warnings = [System.Collections.Generic.List[string]]::new()
try {
    & $block 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) {
            $warnings.Add($_.Message)
        }
    }
}
catch { $failure = $_.Exception.Message }
[pscustomobject]@{
    failure = $failure
    warnings = @($warnings)
    enabled = $script:persistedEnabled
    applyCalls = $script:applyCalls
    disableAttempts = $script:disableAttempts
} | ConvertTo-Json -Compress
'''


@pytest.mark.skipif(PWSH is None, reason="PowerShell is required for the WSUS API mock")
@pytest.mark.parametrize(
    "scenario,error,enabled,apply_calls,disable_attempts",
    [
        ("success", None, False, 1, 1),
        ("apply-fails", "APPLY_FAILED", False, 1, 1),
        ("enable-save-fails", "ENABLE_SAVE_FAILED", False, 0, 1),
        ("cleanup-fails", "DISABLE_SAVE_FAILED", True, 1, 1),
        ("both-fail", "APPLY_FAILED", True, 1, 1),
        ("readback-enabled", "読み戻して確認できない", True, 1, 1),
        ("empty-filter", "絞り込みが空", False, 0, 0),
        ("missing-rule", "1件に特定できない", False, 0, 0),
        ("duplicate-rule", "1件に特定できない", False, 0, 0),
    ],
)
def test_approval_always_attempts_disable_and_preserves_failure(
    tmp_path, scenario, error, enabled, apply_calls, disable_attempts
):
    harness = tmp_path / "wsus-api-mock.ps1"
    harness.write_text(HARNESS, encoding="utf-8")
    result = subprocess.run(
        [
            PWSH, "-NoProfile", "-NonInteractive", "-File", str(harness),
            "-Scenario", scenario,
            "-Document", str(ROOT / "docs/build-package-wsus/05-build-procedure.md"),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    actual = json.loads(result.stdout)
    if error is None:
        assert actual["failure"] is None
    else:
        assert error in actual["failure"]
    assert actual["enabled"] is enabled
    assert actual["applyCalls"] == apply_calls
    assert actual["disableAttempts"] == disable_attempts
    if scenario == "both-fail":
        assert any("DISABLE_SAVE_FAILED" in warning for warning in actual["warnings"])
    else:
        assert actual["warnings"] == []
