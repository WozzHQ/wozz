# wozz

A free GitHub Action that finds expensive "cloud cost bugs" (like N+1 API calls) in your Python code before you merge.

## What It Does

This linter scans your Python codebase for common anti-patterns that can lead to massive cloud bills:

- **N+1 API Calls**: Detects `get_object` or `head_object` calls inside loops that could result in thousands of unnecessary API requests
- **Real-Time Detection**: Catches these issues in pull requests before they hit production
- **Zero Configuration**: Just add the workflow file and you're protected

## Example Bug

```python
# This could cost you $10,000/month in API calls!
for file_name in files:
    response = s3_client.get_object(Bucket='my-bucket', Key=file_name)
    process(response)
```

## Usage

### Step 1: Add the Workflow File

Create a file at `.github/workflows/cost-linter.yml` in your repository:

```yaml
name: wozz

on:
  pull_request:
    branches: [ main, master ]

jobs:
  cost-lint:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
      contents: read
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Run wozz
        id: linter
        uses: YOUR-ORG/cost-bug-linter@main
        continue-on-error: true
      
      - name: Post PR Comment
        if: steps.linter.outcome == 'failure'
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### 🚨 wozz Found Issues!
            
            Our linter found potential cloud cost bugs in this PR.
            
            These *might* be harmless, or they *might* be $10,000/mo bugs.
            
            Review the "Run wozz" step above for details.
            
            To see the real-time cost impact of these patterns, upgrade to our Pro plan.`
            })
```

### Step 2: Create a Pull Request

Once the workflow is added, every pull request will be automatically scanned for cost bugs by wozz. If any are found, you'll see:

1. A failed check on your PR
2. An automatic comment explaining what was found
3. Details in the workflow logs showing exact line numbers

## Detected Patterns

Currently detects:

- **[COST-001]**: `get_object` or `head_object` calls inside `for` or `while` loops

More patterns coming soon!

## Requirements

- Python 3.x in your repository
- GitHub Actions enabled

## How It Works

The linter uses Python's Abstract Syntax Tree (AST) module to parse your code and detect expensive patterns without executing it. It's fast, safe, and works on any Python codebase.

## Local Usage

You can also run the linter locally:

```bash
python3 cost_bug_finder.py file1.py file2.py ...
```

## License

MIT

## Support

Found an issue? Open a GitHub issue or reach out to our team.

