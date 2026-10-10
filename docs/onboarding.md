# Agent onboarding

The first non-demo launch opens **Set up Open One**. The same flow is available from **Settings → Connect agents — guided setup…**, the menu bar’s **Connect agents…**, and an empty Inbox.

1. **Connect agents.** Select Claude Code, Codex, or both. The Open One resolves the installed official CLI, checks its version, and queries its authentication status. Missing CLIs link to official installation instructions. **Sign in…** opens the official CLI’s login command in Terminal; return and choose **Check again** afterward. These checks do not send a model request.
2. **Choose a project.** Use the native folder picker. The folder must exist and be readable. For Codex, choose a trusted Git project. Existing CLI permissions apply; setup adds no permission-bypass flags.
3. **Try it.** **Verify connections** sends a short hello, explicitly asking the agent not to read/change files or use tools. This uses the existing account and may count toward its usage. Each selected provider must return a nonempty assistant response and a native conversation ID through the production Store and AgentRunner. Exit success alone is insufficient. The conversations remain in Inbox.
4. **Continue.** Open Inbox, or choose **Connect my phone** to open the existing Remote access panel. Phone access remains opt-in and requires its normal private transport setup.

**Set up later** and closing the setup window save the choice and stop any active setup check. Setup does not reopen automatically after deferral or completion. Reopen it from Settings or the menu bar whenever needed. Failed connections have an explicit retry; successful checks are reused for the same project. Changing the project invalidates verification. A check times out after 90 seconds and stops only its own process.

Progress is saved in `onboarding.json` under the app’s data root (`OPEN_ONE_HOME` when provided). It stores selected provider names, project path, verified conversation IDs, and completion/deferral flags. Raw authentication output, account details, and credentials are not persisted there. Microphone and screen permissions remain deferred until those features are used.

## Automated verification

```sh
bash scripts/test-onboarding.sh
bash scripts/test.sh
bash scripts/build.sh
```

The onboarding suite uses the actual SwiftUI view, model, Store, and AgentRunner with isolated data directories and fixture CLI subprocesses. It covers missing installations, signed-out and unrecognized authentication, bounded status probes, rapid process exits, project validation, both providers’ stream formats, explicit-send gating, duplicate clicks, saved completion, restart, deferral, corrupt/stale progress, cancellation, retry, failed/empty responses, and timeouts. PNG renders, a JSON report, and logs are written to `.build/onboarding-e2e/<timestamp>/`.

## Packaged native UI verification

```sh
python3 scripts/e2e/onboarding-app.py
```

This copies the built app under a unique bundle identity and launches it with local Claude/Codex fixtures, disabled transcript discovery, and a disposable Git project. Its printed paths identify the app, data root, and project to select. The fixture environment is also stored in the test app’s `LSEnvironment` so a GUI relaunch stays isolated. No real provider request is sent.

Use native UI automation to select both agents, choose the printed project through the folder picker, verify connections, and open Inbox or Remote access. Check that exactly two requests are recorded in `data/fixture-requests.log`, both replies are visible, and `data/onboarding.json` is completed. Quit the fixture, then restart it with:

```sh
python3 scripts/e2e/onboarding-app.py --restart .build/onboarding-ui/<timestamp>
```

Confirm that setup stays closed. Reopen **Connect agents…** from the menu bar to check recovery. A separate fresh fixture can exercise **Set up later** and restart. Screenshots and results belong beside `launch.json` in the fixture directory.

Fixture coverage verifies the application’s integration with supported CLI protocols. Real provider sign-in, billing/account restrictions, and a clean-machine notarized install remain separate release checks.
