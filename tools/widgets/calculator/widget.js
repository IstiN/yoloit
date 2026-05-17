// Calculator widget — pure JS, no network required
(function () {
  const app = document.getElementById('app');

  app.innerHTML = `
    <div style="padding:12px;max-width:280px;margin:0 auto">
      <div id="display"
        style="background:#0f172a;border:1px solid #334155;border-radius:8px;
               padding:12px 16px;margin-bottom:10px;text-align:right;min-height:60px">
        <div id="expr" style="font-size:11px;color:#64748b;min-height:16px;margin-bottom:4px"></div>
        <div id="result" style="font-size:28px;font-weight:700;color:#e2e8f0">0</div>
      </div>
      <div id="keys" style="display:grid;grid-template-columns:repeat(4,1fr);gap:6px"></div>
    </div>`;

  const keys = [
    ['C', '±', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
    ['0', '.', '⌫', '='],
  ];

  const ops = { '÷': '/', '×': '*', '−': '-', '+': '+' };
  let expr = '';
  let resultEl = document.getElementById('result');
  let exprEl = document.getElementById('expr');
  let justCalc = false;

  const keyColors = {
    'C': '#ef4444', '±': '#475569', '%': '#475569', '÷': '#f59e0b',
    '×': '#f59e0b', '−': '#f59e0b', '+': '#f59e0b', '=': '#3b82f6',
    '⌫': '#475569',
  };

  const grid = document.getElementById('keys');
  for (const row of keys) {
    for (const k of row) {
      const btn = document.createElement('button');
      btn.textContent = k;
      const bg = keyColors[k] || '#1e293b';
      btn.style.cssText = `
        background:${bg};border:1px solid #334155;border-radius:8px;
        color:#e2e8f0;font-size:16px;font-weight:600;padding:14px 0;
        cursor:pointer;transition:opacity .1s;
        ${k === '0' ? '' : ''}
      `;
      btn.onmousedown = () => { btn.style.opacity = '0.7'; };
      btn.onmouseup = () => { btn.style.opacity = '1'; };
      btn.onclick = () => press(k);
      grid.appendChild(btn);
    }
  }

  function press(k) {
    if (k === 'C') {
      expr = '';
      resultEl.textContent = '0';
      exprEl.textContent = '';
      justCalc = false;
      return;
    }
    if (k === '⌫') {
      expr = expr.slice(0, -1);
      exprEl.textContent = expr;
      if (!expr) resultEl.textContent = '0';
      return;
    }
    if (k === '=') {
      try {
        const evaled = Function('"use strict"; return (' + expr.replace(/÷/g, '/').replace(/×/g, '*').replace(/−/g, '-') + ')')();
        exprEl.textContent = expr + ' =';
        resultEl.textContent = Number(evaled.toFixed(10)).toString();
        expr = evaled.toString();
        justCalc = true;
      } catch {
        resultEl.textContent = 'Error';
        expr = '';
        justCalc = true;
      }
      return;
    }
    if (k === '±') {
      if (expr.startsWith('-')) expr = expr.slice(1);
      else if (expr) expr = '-' + expr;
      exprEl.textContent = expr;
      return;
    }
    if (k === '%') {
      try {
        const v = Function('"use strict"; return (' + expr.replace(/÷/g, '/').replace(/×/g, '*').replace(/−/g, '-') + ')')();
        expr = (v / 100).toString();
        resultEl.textContent = expr;
        exprEl.textContent = '';
      } catch {}
      return;
    }
    const opMap = { '÷': '/', '×': '*', '−': '-' };
    if (justCalc && /[\d.]/.test(k)) { expr = ''; justCalc = false; }
    expr += opMap[k] || k;
    exprEl.textContent = expr;
    // Live eval preview
    try {
      const preview = Function('"use strict"; return (' + expr.replace(/÷/g, '/').replace(/×/g, '*').replace(/−/g, '-') + ')')();
      if (isFinite(preview)) resultEl.textContent = Number(preview.toFixed(10)).toString();
    } catch {}
  }

  // Keyboard support
  document.addEventListener('keydown', function(e) {
    const map = {
      '0':'0','1':'1','2':'2','3':'3','4':'4','5':'5','6':'6','7':'7','8':'8','9':'9',
      '.':'.', '+':'+', '-':'−', '*':'×', '/':'÷', 'Enter':'=', 'Backspace':'⌫', 'Escape':'C',
    };
    if (map[e.key]) { press(map[e.key]); e.preventDefault(); }
  });
})();
