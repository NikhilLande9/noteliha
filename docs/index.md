<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>noteliha — Documentation</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=DM+Mono:wght@400;500&family=DM+Sans:wght@300;400;500&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
--ink:        #0f0e0d;
--ink-soft:   #6b6560;
--ink-muted:  #b0aaa4;
--paper:      #faf8f5;
--paper-warm: #f2ede6;
--rule:       #e4ddd5;
--teal:       #2a7a6f;
--teal-light: #e0f0ed;
--teal-mid:   #4aada0;
--amber:      #c47a2a;
--red:        #b84040;
}

html { scroll-behavior: smooth; }

body {
font-family: 'DM Sans', sans-serif;
background: var(--paper);
color: var(--ink);
min-height: 100vh;
overflow-x: hidden;
}

/* ── Grain overlay ───────────────────────────────────────────── */
body::before {
content: '';
position: fixed;
inset: 0;
background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='0.03'/%3E%3C/svg%3E");
pointer-events: none;
z-index: 999;
opacity: 0.4;
}

/* ── Layout ──────────────────────────────────────────────────── */
.page {
max-width: 780px;
margin: 0 auto;
padding: 0 28px 100px;
}

/* ── Header ──────────────────────────────────────────────────── */
header {
padding: 72px 0 56px;
position: relative;
}

.header-rule {
width: 40px;
height: 3px;
background: var(--teal);
margin-bottom: 28px;
animation: slideIn 0.6s cubic-bezier(.22,1,.36,1) both;
}

.logo-line {
display: flex;
align-items: baseline;
gap: 0;
animation: fadeUp 0.7s cubic-bezier(.22,1,.36,1) 0.1s both;
}

.logo-note {
font-family: 'DM Serif Display', serif;
font-size: clamp(42px, 8vw, 64px);
color: var(--ink);
letter-spacing: -2px;
line-height: 1;
}

.logo-liha {
font-family: 'DM Serif Display', serif;
font-size: clamp(42px, 8vw, 64px);
color: var(--teal);
letter-spacing: -2px;
line-height: 1;
}

.header-sub {
margin-top: 16px;
font-size: 14px;
font-weight: 400;
color: var(--ink-soft);
letter-spacing: 0.04em;
animation: fadeUp 0.7s cubic-bezier(.22,1,.36,1) 0.2s both;
}

.header-sub span {
color: var(--teal);
font-weight: 500;
}

.doc-badge {
display: inline-flex;
align-items: center;
gap: 6px;
margin-top: 24px;
padding: 6px 12px;
background: var(--teal-light);
border: 1px solid rgba(42,122,111,0.2);
border-radius: 4px;
font-family: 'DM Mono', monospace;
font-size: 11px;
font-weight: 500;
color: var(--teal);
letter-spacing: 0.08em;
text-transform: uppercase;
animation: fadeUp 0.7s cubic-bezier(.22,1,.36,1) 0.3s both;
}

.doc-badge::before {
content: '';
width: 6px;
height: 6px;
background: var(--teal);
border-radius: 50%;
}

/* ── Divider ─────────────────────────────────────────────────── */
.divider {
height: 1px;
background: var(--rule);
margin: 0 0 48px;
animation: fadeUp 0.5s ease 0.35s both;
}

/* ── Section ─────────────────────────────────────────────────── */
.section {
margin-bottom: 52px;
animation: fadeUp 0.7s cubic-bezier(.22,1,.36,1) both;
}

.section:nth-child(1) { animation-delay: 0.4s; }
.section:nth-child(2) { animation-delay: 0.5s; }
.section:nth-child(3) { animation-delay: 0.6s; }
.section:nth-child(4) { animation-delay: 0.7s; }

.section-label {
display: flex;
align-items: center;
gap: 10px;
margin-bottom: 16px;
}

.section-label-text {
font-family: 'DM Mono', monospace;
font-size: 10px;
font-weight: 500;
color: var(--ink-muted);
letter-spacing: 0.14em;
text-transform: uppercase;
}

.section-label-line {
flex: 1;
height: 1px;
background: var(--rule);
}

/* ── Cards ───────────────────────────────────────────────────── */
.card-grid {
display: grid;
gap: 10px;
}

.card-grid.two-col {
grid-template-columns: 1fr 1fr;
}

@media (max-width: 520px) {
.card-grid.two-col { grid-template-columns: 1fr; }
}

.doc-card {
display: flex;
align-items: center;
gap: 16px;
padding: 18px 20px;
background: #fff;
border: 1px solid var(--rule);
border-radius: 8px;
text-decoration: none;
color: inherit;
transition: border-color 0.18s, box-shadow 0.18s, transform 0.18s;
position: relative;
overflow: hidden;
}

.doc-card::after {
content: '';
position: absolute;
inset: 0;
background: linear-gradient(135deg, transparent 60%, var(--teal-light) 100%);
opacity: 0;
transition: opacity 0.2s;
}

.doc-card:hover {
border-color: var(--teal-mid);
box-shadow: 0 4px 20px rgba(42,122,111,0.10);
transform: translateY(-1px);
}

.doc-card:hover::after { opacity: 1; }

.card-icon {
width: 38px;
height: 38px;
border-radius: 8px;
display: flex;
align-items: center;
justify-content: center;
flex-shrink: 0;
font-size: 17px;
position: relative;
z-index: 1;
}

.icon-teal   { background: var(--teal-light); }
.icon-amber  { background: #fdf0dc; }
.icon-red    { background: #fde8e8; }
.icon-slate  { background: #eeedf0; }

.card-body {
flex: 1;
position: relative;
z-index: 1;
}

.card-title {
font-size: 14px;
font-weight: 500;
color: var(--ink);
line-height: 1.3;
}

.card-desc {
font-size: 12px;
color: var(--ink-soft);
margin-top: 2px;
font-weight: 300;
}

.card-arrow {
color: var(--ink-muted);
font-size: 16px;
position: relative;
z-index: 1;
transition: color 0.18s, transform 0.18s;
}

.doc-card:hover .card-arrow {
color: var(--teal);
transform: translateX(3px);
}

/* ── GitHub card ─────────────────────────────────────────────── */
.github-card {
display: flex;
align-items: center;
gap: 16px;
padding: 20px 24px;
background: var(--ink);
border-radius: 8px;
color: #fff;
cursor: default;
position: relative;
overflow: hidden;
}

.github-card::before {
content: '';
position: absolute;
top: -30px; right: -30px;
width: 120px; height: 120px;
border-radius: 50%;
background: rgba(255,255,255,0.04);
}

.github-icon {
width: 40px;
height: 40px;
background: rgba(255,255,255,0.1);
border-radius: 8px;
display: flex;
align-items: center;
justify-content: center;
font-size: 20px;
flex-shrink: 0;
}

.github-body { flex: 1; }

.github-title {
font-size: 14px;
font-weight: 500;
color: #fff;
}

.github-desc {
font-size: 12px;
color: rgba(255,255,255,0.5);
margin-top: 2px;
font-weight: 300;
}

.github-tag {
font-family: 'DM Mono', monospace;
font-size: 10px;
padding: 4px 10px;
background: rgba(255,255,255,0.1);
border-radius: 4px;
color: rgba(255,255,255,0.7);
letter-spacing: 0.06em;
white-space: nowrap;
}

/* ── Footer ──────────────────────────────────────────────────── */
footer {
margin-top: 64px;
padding-top: 28px;
border-top: 1px solid var(--rule);
display: flex;
align-items: center;
justify-content: space-between;
animation: fadeUp 0.6s ease 0.8s both;
}

.footer-left {
font-size: 12px;
color: var(--ink-muted);
}

.footer-left strong {
color: var(--ink-soft);
font-weight: 500;
}

.footer-right {
font-family: 'DM Mono', monospace;
font-size: 10px;
color: var(--ink-muted);
letter-spacing: 0.1em;
}

/* ── Animations ──────────────────────────────────────────────── */
@keyframes slideIn {
from { width: 0; opacity: 0; }
to   { width: 40px; opacity: 1; }
}

@keyframes fadeUp {
from { opacity: 0; transform: translateY(14px); }
to   { opacity: 1; transform: translateY(0); }
}
</style>
</head>
<body>
<div class="page">

  <!-- Header -->
  <header>
    <div class="header-rule"></div>
    <div class="logo-line">
      <span class="logo-note">note</span><span class="logo-liha">liha</span>
    </div>
    <p class="header-sub">Official documentation by <span>Nikhil Lande – Navkon Labs</span></p>
    <div class="doc-badge">Documentation</div>
  </header>

  <div class="divider"></div>

  <!-- Legal -->
  <div class="section">
    <div class="section-label">
      <span class="section-label-text">Legal</span>
      <div class="section-label-line"></div>
    </div>
    <div class="card-grid two-col">
      <a href="PRIVACY_POLICY.md" class="doc-card">
        <div class="card-icon icon-teal">🔒</div>
        <div class="card-body">
          <div class="card-title">Privacy Policy</div>
          <div class="card-desc">Data collection & usage</div>
        </div>
        <span class="card-arrow">→</span>
      </a>
      <a href="TERMS_OF_SERVICE.md" class="doc-card">
        <div class="card-icon icon-teal">📄</div>
        <div class="card-body">
          <div class="card-title">Terms of Service</div>
          <div class="card-desc">Rules & agreements</div>
        </div>
        <span class="card-arrow">→</span>
      </a>
    </div>
  </div>

  <!-- App Store -->
  <div class="section">
    <div class="section-label">
      <span class="section-label-text">App Store Listings</span>
      <div class="section-label-line"></div>
    </div>
    <div class="card-grid two-col">
      <a href="GOOGLE_PLAY_STORE_LISTING.md" class="doc-card">
        <div class="card-icon icon-amber">▶</div>
        <div class="card-body">
          <div class="card-title">Google Play Store</div>
          <div class="card-desc">Android listing copy</div>
        </div>
        <span class="card-arrow">→</span>
      </a>
      <a href="APPLE_APP_STORE_LISTING.md" class="doc-card">
        <div class="card-icon icon-slate">🍎</div>
        <div class="card-body">
          <div class="card-title">Apple App Store</div>
          <div class="card-desc">iOS listing copy</div>
        </div>
        <span class="card-arrow">→</span>
      </a>
    </div>
  </div>

  <!-- Publishing -->
  <div class="section">
    <div class="section-label">
      <span class="section-label-text">Publishing</span>
      <div class="section-label-line"></div>
    </div>
    <div class="card-grid">
      <a href="PUBLISHING_CHECKLIST.md" class="doc-card">
        <div class="card-icon icon-red">✅</div>
        <div class="card-body">
          <div class="card-title">Publishing Checklist</div>
          <div class="card-desc">Pre-release steps for both stores</div>
        </div>
        <span class="card-arrow">→</span>
      </a>
    </div>
  </div>

  <!-- Repository -->
  <div class="section">
    <div class="section-label">
      <span class="section-label-text">Repository</span>
      <div class="section-label-line"></div>
    </div>
    <div class="github-card">
      <div class="github-icon">⌥</div>
      <div class="github-body">
        <div class="github-title">Source Code</div>
        <div class="github-desc">Available on GitHub</div>
      </div>
      <span class="github-tag">github.com</span>
    </div>
  </div>

  <!-- Footer -->
  <footer>
    <div class="footer-left">
      <strong>noteliha</strong> · Navkon Labs
    </div>
    <div class="footer-right">DOCS</div>
  </footer>

</div>
</body>
</html>