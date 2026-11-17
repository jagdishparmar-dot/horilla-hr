# Control plane UI (Tailwind)

Build the compiled stylesheet used by operator templates:

```bash
cd control/frontend
npm install
npm run build
```

Output: `control/static/control/css/control.css` (committed so Docker/tests work without Node).

During template work:

```bash
npm run watch
```