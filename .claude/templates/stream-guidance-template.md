---
stream: X
guidance_type: workaround|alternative|skip|manual
provided: {timestamp}
---

# Stream Recovery Guidance

This file provides guidance for recovering from a blocked stream during parallel execution.

## Approach
{Describe the alternative approach to take}

## Specific Instructions
1. use context7 for current documentation and best practices
2. {Step-by-step guidance}
3. {What to do instead}
4. {What to skip}

## Acceptable Outcomes
- {What partial completion is acceptable}
- {What can be deferred}

## Do Not Attempt
- {What should definitely be avoided}

## Additional Context
{Any other relevant information}

## Example Usage

For a stream blocked by file permission issues:

```markdown
---
stream: 1
guidance_type: workaround  
provided: 2024-08-25T15:30:00Z
---

## Approach
Instead of modifying the protected config.py file directly, create a new configuration module that extends the existing one.

## Specific Instructions
1. Create src/config_extensions.py with the new settings
2. Import and merge settings in the main application
3. Add documentation explaining the extension pattern
4. Skip the direct config.py modifications

## Acceptable Outcomes
- Configuration changes work through the extension pattern
- Original config.py remains untouched
- Tests pass with the new approach

## Do Not Attempt
- Don't try to change file permissions
- Don't attempt sudo or elevated access
- Don't modify system-level configuration files
```

## Guidance Types

### workaround
Use when there's an alternative technical approach that avoids the blocker.

### alternative  
Use when a different implementation strategy should be taken.

### skip
Use when the blocked functionality should be omitted from this iteration.

### manual
Use when human intervention is required outside the automation system.

## Tips for Effective Guidance

1. **Be Specific**: Provide concrete steps, not general suggestions
2. **Consider Dependencies**: Note if your guidance affects other streams
3. **Set Expectations**: Clearly define what "success" looks like
4. **Provide Context**: Explain why this approach is preferred
5. **Test Friendly**: Ensure the guidance leads to testable results