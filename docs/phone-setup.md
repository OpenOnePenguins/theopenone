# The Open One on your phone

Use our dark-mode web app in Safari. It connects to The Open One running on your Mac and continues its tracked conversations in the same provider session and worktree. No Expo, Orca Mobile, Apple Developer account, or TestFlight installation is needed. Phone access is LAN-only; both devices must be on the same local network.

## Local Wi-Fi — LAN only

1. Put the Mac and iPhone on the **same Wi-Fi network**. Keep the Mac awake with The Open One running.
2. Open **Open One menu → Remote access** on the Mac.
3. Click **Connect phone** under **Local Wi-Fi only**. If several LAN addresses appear, select the Wi-Fi/Ethernet interface on the same network as the phone.
4. Scan the QR with **iPhone Camera** and open it in **Safari**. The address should be a local IP such as `http://192.168.1.100:PORT`. The complete link includes a private credential after `#`.
5. Check **Mac online** and the conversation count. Open a conversation that also appears in the Mac app. Compare the worktree, title, and latest messages before sending a small follow-up.
6. Check that the follow-up appears once in the same conversation on the Mac. Reload Safari to check that the conversation and any unsent draft restore correctly.

The bridge binds only to the selected LAN address. It requires the connection credential and rejects foreign hosts and origins. LAN mode uses local HTTP; use it on a trusted network. **Stop & revoke links** ends access. A bridge restart creates a new port and credential, so scan its new QR.

## Which conversations appear?

The phone receives **all active tracked conversations from the same Store used by the Mac app**, in the same order. Archived, individually removed, and untracked-worktree conversations remain excluded, as they are on the Mac. There is no additional 40-conversation phone limit.

Phone Send now commits as soon as the Mac receives the command, without the Mac composer's two-second Undo delay. The phone checks delivery every 250 ms and clears its draft only after confirmed acceptance. Agent startup or an ongoing turn may take longer. After the Mac app restarts, scan the fresh Remote access QR; old phone links are revoked.

If a conversation is visible in Orca but missing from The Open One on the Mac, add that worktree in The Open One’s tracking settings and enable transcript discovery. The phone follows The Open One’s tracked list; it does not maintain a separate Orca conversation database.

Sample connections are labelled in the phone UI. Use a fresh QR from the Mac app to connect to your own conversations.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| Old sample conversation | Disconnect on the phone and scan a fresh QR from the running Mac app. |
| Cannot connect over Local Wi-Fi | Check both devices use the same network; guest Wi-Fi may isolate devices. Allow Open One/Python in the macOS firewall if prompted. |
| `127.0.0.1` or `localhost` link | It is Mac-only. Scan the LAN QR from the current Mac app. |
| Connect screen | Open the complete link including `#…`, or paste it into Connection link. |
| Connection expired | Scan the current QR; the bridge was restarted or revoked. |
| Missing conversation | Compare The Open One’s tracked list on the Mac. Check tracking and archived/removed conversations. |
| Read-only conversation | The provider cannot currently accept a remote reply. Continue or resume it on the Mac first. |
| Delivery uncertain | Check the Mac before sending again. Unconfirmed sends are not automatically replayed. |

For a Home Screen icon, use Safari **Share → Add to Home Screen**. A separate browser session may need the full connection link again. This is the web app, not a signed native build.
