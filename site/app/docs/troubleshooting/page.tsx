import { DocsShell } from "@/components/docs-shell";

export default function TroubleshootingPage() {
  return (
    <DocsShell
      title="Troubleshooting"
      intro="Common issues and quick fixes for first-time setup."
    >
      <h2>No text appears while speaking</h2>
      <ul>
        <li>Confirm microphone permission is enabled.</li>
        <li>Check that the correct microphone is active in macOS sound settings.</li>
        <li>Try restarting Speak after changing permissions.</li>
      </ul>

      <h2>Text does not paste into my app</h2>
      <ul>
        <li>Grant Accessibility permission.</li>
        <li>Confirm your target app allows paste shortcuts.</li>
        <li>Disable and re-enable Accessibility for Speak if behavior is stale.</li>
      </ul>

      <h2>Speech model seems unavailable</h2>
      <ul>
        <li>Ensure you are on macOS 26 or newer.</li>
        <li>Stay online briefly so macOS can fetch language assets if needed.</li>
        <li>Switch language in Settings and retry.</li>
      </ul>

      <h2>App does not open due to security warning</h2>
      <ul>
        <li>In Finder, right-click Speak and choose <strong>Open</strong>.</li>
        <li>Confirm the dialog once. Later launches should work normally.</li>
      </ul>
    </DocsShell>
  );
}
