$PROMPT_FILE = "CLAUDE.md"
$MAX_ITERATIONS = 50
$MODEL = "opus"

if (-not (Test-Path $PROMPT_FILE)) {
  Write-Host "Error: $PROMPT_FILE not found"
  exit 1
}

$ITERATION = 1
while ($ITERATION -le $MAX_ITERATIONS) {
  Write-Host "======================== LOOP $ITERATION ========================"

  type $PROMPT_FILE | claude -p `
    --dangerously-skip-permissions `
    --model $MODEL

  git add .
  git commit -m "Ralph iteration $ITERATION" -ErrorAction SilentlyContinue
  git push -ErrorAction SilentlyContinue

  $ITERATION++

}
Write-Host "Done after $MAX_ITERATIONS iterations."
