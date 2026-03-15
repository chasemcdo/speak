import { DocsShell } from "@/components/docs-shell";

export default function ConversationModePage() {
  return (
    <DocsShell
      title="Conversation Mode"
      intro="Have a hands-free voice conversation with Claude Code. Speak transcribes your voice and sends it to Claude, then reads Claude's response aloud."
    >
      <p>
        This is an experimental feature for fun. The primary interface is the
        hotkey → dictate → paste workflow.
      </p>

      <h2>Prerequisites</h2>
      <ol>
        <li>
          Install{" "}
          <a href="https://claude.com/claude-code" target="_blank" rel="noopener noreferrer">
            Claude Code
          </a>
        </li>
        <li>Complete Speak onboarding (microphone, accessibility permissions)</li>
      </ol>

      <h2>Setup</h2>
      <ol>
        <li>Open Speak → Settings → Conversation Mode.</li>
        <li>
          Click <strong>Set Up</strong> to connect Speak to Claude Code.
        </li>
        <li>
          You should see a green checkmark and &ldquo;Connected to Claude
          Code&rdquo; once setup is complete.
        </li>
      </ol>

      <h2>Usage</h2>
      <ol>
        <li>Open a terminal with Claude Code running.</li>
        <li>Triple-tap your hotkey to enter conversation mode.</li>
        <li>Speak naturally — your voice is transcribed and submitted to Claude automatically.</li>
        <li>Claude responds and Speak reads it back aloud.</li>
        <li>The loop repeats until you exit.</li>
      </ol>

      <h2>Exiting</h2>
      <ul>
        <li>Triple-tap your hotkey again, or</li>
        <li>Say &ldquo;stop conversation&rdquo;, &ldquo;end conversation&rdquo;, or &ldquo;exit conversation&rdquo;</li>
      </ul>

      <h2>Removing</h2>
      <p>
        To disconnect, open Settings → Conversation Mode and click{" "}
        <strong>Remove</strong>. This removes the Speak MCP server entry from
        Claude Code&apos;s configuration.
      </p>
    </DocsShell>
  );
}
