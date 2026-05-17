// Weather widget — uses wttr.in free JSON API (no key required)
(function () {
  const app = document.getElementById('app');

  async function loadWeather(city) {
    app.innerHTML = '<div style="padding:16px;color:#94a3b8">Loading…</div>';
    try {
      const url = `https://wttr.in/${encodeURIComponent(city)}?format=j1`;
      const data = await yoloit.fetchJson(url);
      const cur = data.current_condition[0];
      const area = data.nearest_area[0];
      const areaName = area.areaName[0].value;
      const country = area.country[0].value;
      const tempC = cur.temp_C;
      const tempF = cur.temp_F;
      const desc = cur.weatherDesc[0].value;
      const humidity = cur.humidity;
      const windKph = cur.windspeedKmph;
      const feelsC = cur.FeelsLikeC;

      // Weather icon mapping
      const iconMap = {
        'Clear': '☀️', 'Sunny': '☀️', 'Partly cloudy': '⛅',
        'Cloudy': '☁️', 'Overcast': '☁️', 'Mist': '🌫️',
        'Rain': '🌧️', 'Light rain': '🌦️', 'Heavy rain': '🌧️',
        'Snow': '❄️', 'Thunder': '⛈️', 'Blizzard': '🌨️',
        'Fog': '🌫️', 'Drizzle': '🌦️',
      };
      const icon = Object.keys(iconMap).find(k => desc.toLowerCase().includes(k.toLowerCase()))
        ? iconMap[Object.keys(iconMap).find(k => desc.toLowerCase().includes(k.toLowerCase()))]
        : '🌡️';

      app.innerHTML = `
        <div style="padding:20px;text-align:center">
          <div style="font-size:56px;margin-bottom:4px">${icon}</div>
          <div style="font-size:13px;color:#94a3b8;margin-bottom:8px">${areaName}, ${country}</div>
          <div style="font-size:42px;font-weight:700;color:#e2e8f0">${tempC}°C</div>
          <div style="font-size:13px;color:#94a3b8">${tempF}°F · Feels like ${feelsC}°C</div>
          <div style="font-size:14px;color:#cbd5e1;margin:10px 0">${desc}</div>
          <div style="display:flex;justify-content:center;gap:24px;margin-top:12px;font-size:12px;color:#64748b">
            <div>💧 ${humidity}%</div>
            <div>💨 ${windKph} km/h</div>
          </div>
        </div>
        <div style="text-align:center;margin-top:12px">
          <form onsubmit="event.preventDefault();changeCity(this.city.value)">
            <input name="city" value="${city}"
              style="background:#1e293b;border:1px solid #334155;border-radius:6px;
                     color:#e2e8f0;padding:6px 10px;font-size:12px;width:140px;outline:none">
            <button type="submit"
              style="background:#3b82f6;border:none;border-radius:6px;color:#fff;
                     padding:6px 10px;font-size:12px;cursor:pointer;margin-left:6px">Go</button>
          </form>
        </div>
        <div style="text-align:center;margin-top:8px;font-size:10px;color:#334155">
          via wttr.in · updated ${new Date().toLocaleTimeString()}
        </div>
      `;
    } catch (e) {
      app.innerHTML = `
        <div style="padding:20px;text-align:center">
          <div style="font-size:32px">⚠️</div>
          <div style="color:#f87171;font-size:13px;margin:8px 0">Could not load weather</div>
          <div style="color:#64748b;font-size:11px">${e.message}</div>
          <div style="margin-top:12px">
            <form onsubmit="event.preventDefault();changeCity(this.city.value)">
              <input name="city" placeholder="Enter city…"
                style="background:#1e293b;border:1px solid #334155;border-radius:6px;
                       color:#e2e8f0;padding:6px 10px;font-size:12px;width:140px;outline:none">
              <button type="submit"
                style="background:#3b82f6;border:none;border-radius:6px;color:#fff;
                       padding:6px 10px;font-size:12px;cursor:pointer;margin-left:6px">Go</button>
            </form>
          </div>
        </div>
      `;
    }
  }

  window.changeCity = function(city) {
    if (!city.trim()) return;
    yoloit.storage.set('city', city.trim());
    loadWeather(city.trim());
  };

  // Init — load saved city or default
  yoloit.storage.get('city').then(function(saved) {
    loadWeather(saved || 'London');
  });

  // Auto-refresh every 10 minutes
  setInterval(function() {
    yoloit.storage.get('city').then(function(c) { loadWeather(c || 'London'); });
  }, 10 * 60 * 1000);
})();
