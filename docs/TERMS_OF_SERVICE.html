<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=DM+Mono:wght@400;500&family=DM+Sans:wght@300;400;500&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --ink:        #0f0e0d;
    --ink-soft:   #6b6560;
    --ink-muted:  #b0aaa4;
    --paper:      #faf8f5;
    --rule:       #e4ddd5;
    --teal:       #2a7a6f;
    --teal-light: #e0f0ed;
    --teal-mid:   #4aada0;
  }

  html { scroll-behavior: smooth; }

  body {
    font-family: 'DM Sans', sans-serif;
    background: var(--paper);
    color: var(--ink);
    min-height: 100vh;
    overflow-x: hidden;
  }

  body::before {
    content: '';
    position: fixed;
    inset: 0;
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='0.03'/%3E%3C/svg%3E");
    pointer-events: none;
    z-index: 999;
    opacity: 0.4;
  }

  .page { max-width: 740px; margin: 0 auto; padding: 0 28px 100px; }

  .back {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin: 36px 0 0;
    font-family: 'DM Mono', monospace;
    font-size: 11px;
    font-weight: 500;
    color: var(--teal);
    text-decoration: none;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    transition: opacity 0.15s;
  }
  .back:hover { opacity: 0.7; }
  .back::before { content: '←'; font-size: 13px; }

  header { padding: 40px 0 48px; }

  .header-rule {
    width: 40px; height: 3px;
    background: var(--teal);
    margin-bottom: 24px;
    animation: slideIn 0.6s cubic-bezier(.22,1,.36,1) both;
  }

  .header-title {
    font-family: 'DM Serif Display', serif;
    font-size: clamp(32px, 6vw, 48px);
    color: var(--ink);
    letter-spacing: -1.5px;
    line-height: 1.1;
    animation: fadeUp 0.7s cubic-bezier(.22,1,.36,1) 0.1s both;
  }
  .header-title span { color: var(--teal); }

  .header-meta {
    display: flex; flex-wrap: wrap; gap: 16px;
    margin-top: 20px;
    animation: fadeUp 0.7s cubic-bezier(.22,1,.36,1) 0.2s both;
  }

  .meta-chip {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 5px 11px;
    background: var(--teal-light);
    border: 1px solid rgba(42,122,111,0.2);
    border-radius: 4px;
    font-family: 'DM Mono', monospace;
    font-size: 10.5px; font-weight: 500;
    color: var(--teal); letter-spacing: 0.06em;
  }

  .divider { height: 1px; background: var(--rule); margin: 0 0 52px; animation: fadeUp 0.5s ease 0.3s both; }

  .toc {
    background: #fff; border: 1px solid var(--rule);
    border-radius: 10px; padding: 24px 28px; margin-bottom: 52px;
    animation: fadeUp 0.6s cubic-bezier(.22,1,.36,1) 0.35s both;
  }
  .toc-label {
    font-family: 'DM Mono', monospace; font-size: 10px; font-weight: 500;
    color: var(--ink-muted); letter-spacing: 0.14em; text-transform: uppercase; margin-bottom: 14px;
  }
  .toc-list { list-style: none; display: grid; grid-template-columns: 1fr 1fr; gap: 6px 24px; }
  @media (max-width: 500px) { .toc-list { grid-template-columns: 1fr; } }
  .toc-list a { display: flex; align-items: baseline; gap: 8px; font-size: 13px; color: var(--ink-soft); text-decoration: none; transition: color 0.15s; }
  .toc-list a:hover { color: var(--teal); }
  .toc-num { font-family: 'DM Mono', monospace; font-size: 10px; color: var(--teal); font-weight: 500; min-width: 18px; }

  .section { margin-bottom: 56px; animation: fadeUp 0.6s cubic-bezier(.22,1,.36,1) both; }

  .section-header {
    display: flex; align-items: center; gap: 12px;
    margin-bottom: 20px; padding-bottom: 14px;
    border-bottom: 1px solid var(--rule);
  }
  .section-num {
    font-family: 'DM Mono', monospace; font-size: 11px; font-weight: 500;
    color: var(--teal); background: var(--teal-light);
    padding: 3px 8px; border-radius: 4px; letter-spacing: 0.06em; white-space: nowrap; flex-shrink: 0;
  }
  .section-title { font-family: 'DM Serif Display', serif; font-size: 22px; color: var(--ink); letter-spacing: -0.5px; }

  .subsection { margin-bottom: 28px; }
  .subsection-title {
    font-family: 'DM Mono', monospace; font-size: 10.5px; font-weight: 500;
    color: var(--ink-soft); letter-spacing: 0.1em; text-transform: uppercase; margin-bottom: 10px;
  }

  p { font-size: 14.5px; color: var(--ink-soft); line-height: 1.75; margin-bottom: 12px; font-weight: 300; }
  p strong { color: var(--ink); font-weight: 500; }

  .item-list { list-style: none; margin: 8px 0 16px; }
  .item-list li {
    display: flex; align-items: flex-start; gap: 10px;
    font-size: 14px; color: var(--ink-soft); line-height: 1.6;
    padding: 5px 0; font-weight: 300;
    border-bottom: 1px solid var(--rule);
  }
  .item-list li:last-child { border-bottom: none; }
  .item-list li::before {
    content: ''; width: 5px; height: 5px;
    background: var(--teal-mid); border-radius: 50%;
    margin-top: 8px; flex-shrink: 0;
  }

  .step-list { list-style: none; counter-reset: steps; margin: 8px 0 16px; }
  .step-list li {
    counter-increment: steps;
    display: flex; align-items: flex-start; gap: 12px;
    font-size: 14px; color: var(--ink-soft); line-height: 1.6;
    padding: 8px 0; border-bottom: 1px solid var(--rule); font-weight: 300;
  }
  .step-list li:last-child { border-bottom: none; }
  .step-list li::before {
    content: counter(steps);
    font-family: 'DM Mono', monospace; font-size: 10px; font-weight: 500;
    color: var(--teal); background: var(--teal-light);
    border-radius: 50%; width: 20px; height: 20px;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0; margin-top: 2px;
  }

  .info-card {
    background: #fff; border: 1px solid var(--rule);
    border-left: 3px solid var(--teal);
    border-radius: 0 8px 8px 0; padding: 16px 20px; margin: 12px 0 20px;
  }
  .info-card p { margin: 0; }

  .warning-card {
    background: #fff8f0; border: 1px solid #f0ddc0;
    border-left: 3px solid #c47a2a;
    border-radius: 0 8px 8px 0; padding: 16px 20px; margin: 12px 0 20px;
  }
  .warning-card p { margin: 0; color: #7a5020; }

  code {
    font-family: 'DM Mono', monospace; font-size: 12.5px;
    background: var(--teal-light); color: var(--teal);
    padding: 2px 6px; border-radius: 4px;
  }

  a.external { color: var(--teal); text-decoration: none; border-bottom: 1px solid rgba(42,122,111,0.3); transition: border-color 0.15s; }
  a.external:hover { border-color: var(--teal); }

  .contact-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 12px; }
  @media (max-width: 500px) { .contact-grid { grid-template-columns: 1fr; } }
  .contact-item { background: #fff; border: 1px solid var(--rule); border-radius: 8px; padding: 14px 16px; }
  .contact-label { font-family: 'DM Mono', monospace; font-size: 9.5px; font-weight: 500; color: var(--ink-muted); letter-spacing: 0.12em; text-transform: uppercase; margin-bottom: 4px; }
  .contact-value { font-size: 13.5px; color: var(--ink); font-weight: 400; }
  .contact-value a { color: var(--teal); text-decoration: none; }

  footer { padding-top: 28px; border-top: 1px solid var(--rule); display: flex; align-items: center; justify-content: space-between; }
  .footer-left { font-size: 12px; color: var(--ink-muted); }
  .footer-left strong { color: var(--ink-soft); font-weight: 500; }
  .footer-right { font-family: 'DM Mono', monospace; font-size: 10px; color: var(--ink-muted); letter-spacing: 0.1em; }

  @keyframes slideIn { from { width: 0; opacity: 0; } to { width: 40px; opacity: 1; } }
  @keyframes fadeUp { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: translateY(0); } }
</style>

<div class="page">

  <a href="index.html" class="back">Documentation</a>

  <header>
    <div class="header-rule"></div>
    <h1 class="header-title">Terms of <span>Service</span></h1>
    <div class="header-meta">
      <span class="meta-chip">Effective: March 2026</span>
      <span class="meta-chip">Version 1.0</span>
      <span class="meta-chip">noteliha</span>
    </div>
  </header>

  <div class="divider"></div>

  <div class="toc">
    <div class="toc-label">Contents</div>
    <ol class="toc-list">
      <li><a href="#s1"><span class="toc-num">01</span>Acceptance of Terms</a></li>
      <li><a href="#s2"><span class="toc-num">02</span>Use License</a></li>
      <li><a href="#s3"><span class="toc-num">03</span>Intellectual Property</a></li>
      <li><a href="#s4"><span class="toc-num">04</span>User Responsibilities</a></li>
      <li><a href="#s5"><span class="toc-num">05</span>Google Drive Integration</a></li>
      <li><a href="#s6"><span class="toc-num">06</span>Disclaimer of Warranties</a></li>
      <li><a href="#s7"><span class="toc-num">07</span>Limitation of Liability</a></li>
      <li><a href="#s8"><span class="toc-num">08</span>Indemnification</a></li>
      <li><a href="#s9"><span class="toc-num">09</span>Modifications to Service</a></li>
      <li><a href="#s10"><span class="toc-num">10</span>Termination</a></li>
      <li><a href="#s11"><span class="toc-num">11</span>Fees and Payments</a></li>
      <li><a href="#s12"><span class="toc-num">12</span>Governing Law</a></li>
      <li><a href="#s13"><span class="toc-num">13</span>Severability & Waiver</a></li>
      <li><a href="#s14"><span class="toc-num">14</span>Contact</a></li>
    </ol>
  </div>

  <!-- 1 -->
  <div class="section" id="s1">
    <div class="section-header"><span class="section-num">01</span><h2 class="section-title">Acceptance of Terms</h2></div>
    <p>By downloading, installing, or using the noteliha mobile application ("Service", "App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree, please do not use this Service.</p>
    <p>The noteliha application is operated by <strong>Navkon Labs</strong>, an independent software business owned and operated by <strong>Nikhil Lande</strong>, based in <strong>Kharghar, Maharashtra, India</strong>.</p>
    <p>Your continued use of noteliha constitutes acceptance of all terms, conditions, and notices contained herein. If you do not agree, you must uninstall the application and discontinue use immediately.</p>
  </div>

  <!-- 2 -->
  <div class="section" id="s2">
    <div class="section-header"><span class="section-num">02</span><h2 class="section-title">Use License</h2></div>
    <p>We grant you a limited, non-exclusive, non-transferable, revocable license to use noteliha for personal, non-commercial purposes only, on any compatible mobile device you own or control.</p>
    <div class="subsection">
      <div class="subsection-title">Prohibited Behaviour</div>
      <p>You agree not to:</p>
      <ul class="item-list">
        <li>Reverse engineer, decompile, or attempt to derive the source code of noteliha</li>
        <li>Modify or create derivative works based on noteliha</li>
        <li>Remove or obscure any proprietary notice or label</li>
        <li>Use noteliha for any illegal purpose or in violation of applicable laws</li>
        <li>Attempt to gain unauthorized access to noteliha or related systems</li>
        <li>Use noteliha to develop competing products or services</li>
        <li>Sell, rent, lease, or otherwise transfer your rights to use noteliha</li>
        <li>Use automated tools to access the Service</li>
      </ul>
    </div>
  </div>

  <!-- 3 -->
  <div class="section" id="s3">
    <div class="section-header"><span class="section-num">03</span><h2 class="section-title">Intellectual Property</h2></div>
    <div class="subsection">
      <div class="subsection-title">3.1 — Ownership</div>
      <p>noteliha and all of its original content, features, and functionality are owned by <strong>Navkon Labs</strong> and are protected by applicable copyright, trademark, and intellectual property laws.</p>
    </div>
    <div class="subsection">
      <div class="subsection-title">3.2 — Your Content</div>
      <p>You retain all rights to content you create in noteliha ("Your Content"). By using noteliha, you grant us a limited, worldwide, non-exclusive, royalty-free license solely to:</p>
      <ul class="item-list">
        <li>Store Your Content locally on your device</li>
        <li>Backup Your Content to your personal Google Drive account when you choose to enable this feature</li>
        <li>Display Your Content within the Service on your device</li>
      </ul>
      <p>This license exists only to operate the app on your behalf. We do not access, analyze, or use Your Content for any other purpose.</p>
    </div>
    <div class="subsection">
      <div class="subsection-title">3.3 — Feedback</div>
      <p>We may use any feedback or suggestions you provide regarding noteliha without obligation to you, except as prohibited by law.</p>
    </div>
  </div>

  <!-- 4 -->
  <div class="section" id="s4">
    <div class="section-header"><span class="section-num">04</span><h2 class="section-title">User Responsibilities</h2></div>
    <div class="subsection">
      <div class="subsection-title">4.1 — Account Security</div>
      <ul class="item-list">
        <li>You are responsible for maintaining the confidentiality of your Google account credentials</li>
        <li>You are responsible for all activities that occur under your account</li>
        <li>Notify us immediately of any unauthorized use of your account</li>
        <li>We are not responsible for any unauthorized access to your account</li>
      </ul>
    </div>
    <div class="subsection">
      <div class="subsection-title">4.2 — Acceptable Use</div>
      <p>You agree to use noteliha only for lawful purposes and in a way that does not infringe upon the rights of others.</p>
    </div>
  </div>

  <!-- 5 -->
  <div class="section" id="s5">
    <div class="section-header"><span class="section-num">05</span><h2 class="section-title">Google Drive Integration</h2></div>
    <div class="subsection">
      <div class="subsection-title">5.1 — Google API Services</div>
      <p>noteliha uses Google APIs for authentication and optional cloud storage. Your use of these services is also subject to Google's own terms and policies:</p>
      <ul class="item-list">
        <li><a href="https://policies.google.com/terms" class="external" target="_blank">Google Terms of Service</a></li>
        <li><a href="https://policies.google.com/privacy" class="external" target="_blank">Google Privacy Policy</a></li>
        <li><a href="https://developers.google.com/terms/api-services-user-data-policy" class="external" target="_blank">Google API Services User Data Policy</a></li>
      </ul>
    </div>
    <div class="subsection">
      <div class="subsection-title">5.2 — OAuth Scope</div>
      <p>By signing in with Google, you authorize noteliha to access your Google account email and profile information, and to create and manage files in a dedicated folder on your Google Drive.</p>
      <div class="info-card">
        <p>noteliha requests only the <strong>Google Drive <code>drive.file</code> scope</strong>, which restricts access to files created by noteliha. It cannot access any other files in your Drive.</p>
      </div>
    </div>
    <div class="subsection">
      <div class="subsection-title">5.3 — Backup Control</div>
      <ul class="item-list">
        <li>Syncing to Google Drive is optional and requires your explicit action</li>
        <li>You control when backups are performed</li>
        <li>You can sign out at any time to disable sync</li>
        <li>You can delete your backup by removing the <code>.liha_notes_app</code> folder from Google Drive</li>
        <li>Signing out does not automatically delete existing Drive backups</li>
      </ul>
    </div>
  </div>

  <!-- 6 -->
  <div class="section" id="s6">
    <div class="section-header"><span class="section-num">06</span><h2 class="section-title">Disclaimer of Warranties</h2></div>
    <div class="warning-card">
      <p>noteliha is provided "as-is" and "as available" without warranty of any kind, express or implied.</p>
    </div>
    <p>We do not warrant that noteliha will be uninterrupted or error-free, that defects will be corrected, or that the results obtained from using it will be accurate or reliable.</p>
    <p>While we implement reasonable security measures, <strong>we do not guarantee that your data will not be lost</strong>. You are responsible for maintaining your own backups of important data.</p>
  </div>

  <!-- 7 -->
  <div class="section" id="s7">
    <div class="section-header"><span class="section-num">07</span><h2 class="section-title">Limitation of Liability</h2></div>
    <p>To the fullest extent permitted by applicable law, Navkon Labs and Nikhil Lande shall not be liable for any direct, indirect, incidental, special, consequential, or punitive damages, including lost profits, lost data, or business interruption, arising from or related to your use of or inability to use noteliha.</p>
    <p>This limitation applies even if Navkon Labs has been advised of the possibility of such damages.</p>
  </div>

  <!-- 8 -->
  <div class="section" id="s8">
    <div class="section-header"><span class="section-num">08</span><h2 class="section-title">Indemnification</h2></div>
    <p>You agree to indemnify and hold harmless Navkon Labs and Nikhil Lande from any claims, damages, losses, liabilities, and expenses arising from your use of noteliha, your violation of these Terms, your violation of applicable laws, or your infringement of any third-party rights.</p>
  </div>

  <!-- 9 -->
  <div class="section" id="s9">
    <div class="section-header"><span class="section-num">09</span><h2 class="section-title">Modifications to Service</h2></div>
    <p>We reserve the right to modify or discontinue the Service at any time. Significant changes may be communicated through in-app notifications or app store updates. Your continued use of noteliha after modifications constitutes acceptance of the changes.</p>
  </div>

  <!-- 10 -->
  <div class="section" id="s10">
    <div class="section-header"><span class="section-num">10</span><h2 class="section-title">Termination</h2></div>
    <div class="subsection">
      <div class="subsection-title">By You</div>
      <ol class="step-list">
        <li>Sign out of your Google account within the app</li>
        <li>Uninstall the application</li>
      </ol>
    </div>
    <div class="subsection">
      <div class="subsection-title">By Navkon Labs</div>
      <p>We may terminate access if users violate these Terms or abuse the Service.</p>
    </div>
    <div class="subsection">
      <div class="subsection-title">Effect of Termination</div>
      <ul class="item-list">
        <li>Your right to use the app ceases immediately</li>
        <li>Local data remains on your device until you uninstall</li>
        <li>Google Drive backups remain unless you manually delete them</li>
      </ul>
    </div>
  </div>

  <!-- 11 -->
  <div class="section" id="s11">
    <div class="section-header"><span class="section-num">11</span><h2 class="section-title">Fees and Payments</h2></div>
    <p>noteliha is currently <strong>free to use</strong>. Navkon Labs reserves the right to introduce optional paid features in the future with prior notice.</p>
  </div>

  <!-- 12 -->
  <div class="section" id="s12">
    <div class="section-header"><span class="section-num">12</span><h2 class="section-title">Governing Law</h2></div>
    <p>These Terms are governed by the <strong>laws of India</strong>. Any disputes shall fall under the jurisdiction of the courts located in <strong>Maharashtra, India</strong>.</p>
    <p>Users agree to first attempt informal resolution by contacting <a href="mailto:navkon9@gmail.com" class="external">navkon9@gmail.com</a> before pursuing any formal dispute process.</p>
  </div>

  <!-- 13 -->
  <div class="section" id="s13">
    <div class="section-header"><span class="section-num">13</span><h2 class="section-title">Severability & Waiver</h2></div>
    <p>If any provision of these Terms is found to be invalid or unenforceable, the remaining provisions shall remain in full effect. Failure to enforce any provision of these Terms does not constitute a waiver of that provision.</p>
    <p>These Terms and the Privacy Policy constitute the entire agreement between you and Navkon Labs regarding use of the Service.</p>
  </div>

  <!-- 14 -->
  <div class="section" id="s14">
    <div class="section-header"><span class="section-num">14</span><h2 class="section-title">Contact</h2></div>
    <p>For questions about these Terms, contact:</p>
    <div class="contact-grid">
      <div class="contact-item">
        <div class="contact-label">Support Email</div>
        <div class="contact-value"><a href="mailto:navkon9@gmail.com">navkon9@gmail.com</a></div>
      </div>
      <div class="contact-item">
        <div class="contact-label">Developer Email</div>
        <div class="contact-value"><a href="mailto:nikhillande9@gmail.com">nikhillande9@gmail.com</a></div>
      </div>
      <div class="contact-item">
        <div class="contact-label">Developer</div>
        <div class="contact-value">Nikhil Lande</div>
      </div>
      <div class="contact-item">
        <div class="contact-label">Organization</div>
        <div class="contact-value">Navkon Labs, Kharghar, Maharashtra, India</div>
      </div>
    </div>
  </div>

  <footer>
    <div class="footer-left"><strong>noteliha</strong> · Navkon Labs</div>
    <div class="footer-right">TERMS OF SERVICE v1.0</div>
  </footer>

</div>