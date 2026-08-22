# Parse GNU df --output=pcent,target without losing spaces in the mount target.
# The first field is always Use%; every remaining field belongs to the target.
NR == 1 { next }
{
  percent = $1
  sub(/%$/, "", percent)
  $1 = ""
  sub(/^[[:space:]]+/, "", $0)
  if ((percent + 0) > threshold) {
    print $0 " " percent "%"
  }
}
