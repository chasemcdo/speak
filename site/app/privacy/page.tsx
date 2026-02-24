import { SiteChrome } from "@/components/site-chrome";

export default function PrivacyPage() {
  return (
    <SiteChrome>
      <section className="privacy-section">
        <div className="site-container privacy-card">
          <h1>Privacy</h1>
          <p>
            Speak is designed for on-device dictation. Audio processing is done
            using Apple&apos;s local speech APIs.
          </p>
          <p>
            The app does not require a cloud account or subscription to perform
            core transcription.
          </p>
          <p>
            Permissions requested by Speak are only used for dictation input,
            speech processing access, and paste behavior into active apps.
          </p>
        </div>
      </section>
    </SiteChrome>
  );
}
