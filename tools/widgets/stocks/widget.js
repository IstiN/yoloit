// Stocks widget — uses Yahoo Finance query (unofficial, no key needed)
(function () {
  const DEFAULT_SYMBOLS = ['AAPL', 'MSFT', 'GOOGL', 'NVDA', 'TSLA'];
  const app = document.getElementById('app');

  function fmt(n) { return n >= 0 ? '+' + n.toFixed(2) : n.toFixed(2); }

  async function loadQuotes(symbols) {
    // Yahoo Finance v8 — free, no auth, CORS-open endpoint
    const url = `https://query1.finance.yahoo.com/v8/finance/spark?symbols=${symbols.join(',')}&range=1d&interval=5m`;
    const data = await yoloit.fetchJson(url);
    return data;
  }

  // Lightweight quote using Yahoo Finance v7 summary
  async function loadSummary(symbols) {
    const qs = symbols.join('%2C');
    const url = `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${qs}&fields=regularMarketPrice,regularMarketChangePercent,regularMarketChange,shortName`;
    return yoloit.fetchJson(url);
  }

  async function load(symbols) {
    app.innerHTML = '<div style="padding:16px;color:#94a3b8">Loading…</div>';
    try {
      const data = await loadSummary(symbols);
      const quotes = data.quoteResponse.result;
      let html = `<div style="padding:12px">
        <div style="font-size:11px;color:#475569;margin-bottom:10px;text-align:right">
          📈 ${new Date().toLocaleTimeString()}
        </div>`;
      for (const q of quotes) {
        const chg = q.regularMarketChangePercent || 0;
        const chgAbs = q.regularMarketChange || 0;
        const color = chg >= 0 ? '#4ade80' : '#f87171';
        const bg = chg >= 0 ? '#052e16' : '#2d0a0a';
        html += `
          <div style="display:flex;align-items:center;justify-content:space-between;
                      padding:10px 12px;margin-bottom:6px;border-radius:8px;
                      background:#1e293b;border:1px solid #334155">
            <div>
              <div style="font-size:13px;font-weight:700;color:#e2e8f0">${q.symbol}</div>
              <div style="font-size:10px;color:#64748b;max-width:120px;overflow:hidden;
                          text-overflow:ellipsis;white-space:nowrap">${q.shortName || ''}</div>
            </div>
            <div style="text-align:right">
              <div style="font-size:14px;font-weight:700;color:#f1f5f9">
                $${(q.regularMarketPrice || 0).toFixed(2)}
              </div>
              <div style="font-size:11px;padding:2px 6px;border-radius:4px;
                          background:${bg};color:${color}">
                ${fmt(chgAbs)} (${fmt(chg)}%)
              </div>
            </div>
          </div>`;
      }
      html += `</div>
        <div style="padding:0 12px 8px;text-align:center">
          <input id="sym-input" placeholder="AAPL,TSLA,NVDA…" value="${symbols.join(',')}"
            style="background:#1e293b;border:1px solid #334155;border-radius:6px;
                   color:#e2e8f0;padding:6px 10px;font-size:11px;width:160px;outline:none">
          <button onclick="updateSymbols()"
            style="background:#3b82f6;border:none;border-radius:6px;color:#fff;
                   padding:6px 10px;font-size:11px;cursor:pointer;margin-left:6px">Update</button>
        </div>
        <div style="text-align:center;font-size:10px;color:#334155;padding-bottom:8px">
          via Yahoo Finance · auto-refresh 2m</div>`;
      app.innerHTML = html;
    } catch (e) {
      app.innerHTML = `<div style="padding:16px;color:#f87171;font-size:13px">
        ⚠️ ${e.message}</div>`;
    }
  }

  window.updateSymbols = function() {
    const val = document.getElementById('sym-input').value.trim();
    if (!val) return;
    const syms = val.split(',').map(s => s.trim().toUpperCase()).filter(Boolean);
    yoloit.storage.set('symbols', syms);
    load(syms);
  };

  yoloit.panel.setTitle('Stocks');
  yoloit.storage.get('symbols').then(function(saved) {
    load(saved || DEFAULT_SYMBOLS);
  });

  setInterval(function() {
    yoloit.storage.get('symbols').then(function(s) { load(s || DEFAULT_SYMBOLS); });
  }, 2 * 60 * 1000);
})();
