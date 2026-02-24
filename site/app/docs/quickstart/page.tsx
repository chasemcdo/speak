import Image from "next/image";
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
        <li>
          If macOS blocks launch, open System Settings &gt; Privacy &amp; Security,
          then click <strong>Open Anyway</strong> for Speak.
        </li>
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
        <li>Hold <code>fn</code> to start dictation.</li>
        <li>Release <code>fn</code> to confirm and paste.</li>
      </ol>
      <figure className="flow-figure">
        <Image
          src="/dictation-flow.svg"
          alt="Dictation flow from holding fn to pasting output"
          width={1200}
          height={260}
          sizes="(max-width: 768px) 100vw, 800px"
        />
      </figure>

      <h2>Build from source (optional)</h2>
      <pre>
        <code>{`git clone https://github.com/chasemcdo/speak.git
cd speak
make app`}</code>
      </pre>
    </DocsShell>
  );
}
