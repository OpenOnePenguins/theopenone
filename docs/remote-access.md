# Phone access

Remote access is exclusively for continuing The Open One conversations on your phone. It stays off after relaunch.

Start with the [iPhone setup and test guide](phone-setup.md).

- **Local Wi-Fi only:** click Connect phone and scan the QR in Safari. The bridge binds only to a selected private IPv4 interface. Both devices must be on the same LAN.

The product does not start public tunnels, expose a remote-machine setup flow, or require an Orca mobile runtime.

## Transport and validation

Every API call requires the random bearer token carried in the link’s fragment. The web app removes that fragment from browser history and saves the credential in session storage. Stop & revoke links ends access. The credential is a connection link, not a per-device identity.

Hosts and browser origins must match the selected LAN interface. There is no cross-origin access. Phone links require an RFC1918 LAN IPv4 address; loopback is accepted for local development. Tailscale addresses, public IPs and remote hostnames are rejected. The Mac launcher only binds to a current Wi-Fi/Ethernet LAN address and never configures HTTPS forwarding.

The phone receives all active tracked conversations from the Mac Store, in the same order, with their latest 20 visible messages, capped at 8,000 characters each. It preserves provider/session/worktree identity through an opaque key. Removed, archived and untracked conversations follow the Mac’s filtering rules. Filesystem paths, credentials, hidden reasoning and working-memory notes are excluded.

Each send has a durable operation ID. The bridge deduplicates repeated operations, checks the current question and recipient, and expires commands after 30 seconds. An explicit phone Send commits as soon as the Mac consumes the command, revalidating identity and replacement questions before delivery. The Mac composer retains its two-second Undo interval; phone sends do not wait through it. Receipts distinguish queued, staged, submitting, delivered, rejected and uncertain delivery. The phone checks pending receipts every 250 ms without overlapping requests and refreshes just the selected conversation. Unconfirmed sends are never automatically replayed.

Unsupported provider sessions and Herdr-only control remain read-only. Terminal approval keys and creating new agents are outside this phone flow.

The web app lives in [mobile](../mobile/README.md). Export it before building the Mac bundle.
