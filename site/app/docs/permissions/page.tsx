import { DocsShell } from "@/components/docs-shell";

export default function PermissionsPage() {
  return (
    <DocsShell
      title="Permissions"
      intro="Speak requires three macOS permissions to deliver its hotkey-to-paste workflow."
    >
      <h2>Microphone</h2>
      <p>
        Needed to capture your voice input from <code>AVAudioEngine</code>.
        Without this, transcription cannot start.
      </p>

      <h2>Speech Recognition</h2>
      <p>
        Needed so Apple&apos;s speech modules can transcribe audio locally on your
        machine.
      </p>

      <h2>Accessibility</h2>
      <p>
        Needed to paste transcribed text back into the app you were typing in.
        Speak uses this to simulate the final paste action reliably.
      </p>

      <h2>If a permission was denied</h2>
      <ol>
        <li>Open macOS System Settings.</li>
        <li>Go to Privacy &amp; Security.</li>
        <li>Find the permission category and enable Speak.</li>
        <li>Restart Speak and try again.</li>
      </ol>
    </DocsShell>
  );
}
