# Tool approvals

Tool approval makes chosen platform tools wait for a person before they run. It is opt-in for each
organisation, and Quant turns it on and sets which tools need approval. There is no self-serve
switch: contact Quant to enable it or to change the tool list.

## What happens to a tool call

1. The model calls a tool that needs approval. The tool does **not** run. The tool result is
   `pending_approval` with a proposal ID (`p_...`), and the model tells the user that the call waits
   for approval.
2. A person decides in the dashboard (below) or, for an interactive request, in the app that made
   it (QuantCode).
3. An approved call runs once. On the user's **next turn** the conversation starts with a notice:
   `[Platform notice] Proposal p_... (tool <name>): approved and run.` The model reads the result
   with `check_tool_execution_status` and the proposal ID.
4. Other outcomes also arrive as a notice: rejected (with the reason, if one was given), failed,
   expired (not decided in time; it did not run) or blocked (the organisation's policy or AI switch
   stopped it).

A proposal waits until it is decided or it expires. Ask Quant for your organisation's approval
time. Do not make the model call the same tool again for the same action while it waits.

## Decide in the dashboard

AI Services, **Approvals**. The page lists proposals with status, tool, effect, agent, requester,
created and expiry times, decision and outcome. Filter by status: pending approval, approved,
executing, rejected, expired, blocked, complete, failed.

| Action | Use |
|---|---|
| **Approve** | Run this one call |
| **Approve for session** | Run this call, and your later calls of the same tool in the same session, without a new prompt. Only for your own interactive request, and only when your organisation allows session approvals. It ends after a limited time or when the organisation's AI settings change |
| **Reject** | Do not run it. Type an optional reason (up to 500 characters) first; the model sees it |

- People with the AI governance approve permission decide any proposal. Organisation owners and
  admins have it by default.
- Other users can decide only their own proposals. If the organisation requires a separate approver,
  the page shows "An approver must decide."
- The page never shows tool arguments.

## QuantCode

When your organisation has approval prompts, QuantCode shows a prompt in the terminal:
"Cloud tool `<name>` (<effect>) needs your approval", with the expiry time.

| Choice | Result |
|---|---|
| Approve once | Runs this call |
| Approve for this session | Shown only when the session scope is allowed. Covers your later calls of the same tool in this session |
| Reject | Asks for an optional reason, then rejects |
| Decide later, or **Escape** | Closes the prompt with **no** decision. The proposal stays pending; decide it later on the Approvals page |

- `quantcode run`, autonomous mode and editor integrations (ACP) never answer an approval prompt,
  also with `--dangerously-skip-permissions`. A person decides those calls on the Approvals page.
- `quantcode run` exits with code 1 when a turn ends with an error, for example when the stream
  drops while a cloud tool runs. Check the exit code in scripts and CI.
- If a prompt is lost (closed terminal, dropped connection), decide on the Approvals page.

## Problems

| Symptom | Cause | Fix |
|---|---|---|
| Tool result `pending_approval`, nothing runs | The tool needs approval in this organisation | Decide on the Approvals page; the result arrives on the next turn |
| No Approvals entries, or "Approvals are not available" | Tool approval is not on for the organisation | Contact Quant |
| "Approve for session" missing | Not your interactive request, or session approvals are off | Use Approve |
| "An approver must decide." | The organisation requires a separate approver | Ask a person with the approve permission |
| Result never appears in the chat | No new user turn after the decision, or the session expired | Send the next message; the outcome also shows on the Approvals page |
