import { DocsShell } from "@/components/docs-shell";

export default function QuickStartPage() {
  return (
    <DocsShell
      title="Quick Start"
      intro="Install Speak and run your first dictation session with the default workflow."
    >
      <h2>1. Install</h2>
      <ol>
        <li>Download the latest <strong>Speak.dmg</strong> from Releases.</li>
        <li>Drag Speak into your Applications folder.</li>
        <li>On first launch, right-click Speak and choose <strong>Open</strong>.</li>
      </ol>

      <h2>2. Complete onboarding</h2>
      <ol>
        <li>Enable Microphone.</li>
        <li>Enable Speech Recognition.</li>
        <li>Enable Accessibility so Speak can paste text into other apps.</li>
      </ol>

      <h2>3. Dictate text</h2>
      <ol>
        <li>Focus any text field.</li>
        <li>Press the dictation hotkey (<code>fn</code> by default).</li>
        <li>Speak, then press the hotkey again to confirm and paste.</li>
      </ol>

      <h2>Build from source (optional)</h2>
      <pre>
        <code>{`git clone https://github.com/chasemcdo/speak.git
cd speak
make app`}</code>
      </pre>
    </DocsShell>
  );
}
