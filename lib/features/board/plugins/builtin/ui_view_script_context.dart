/// Bootstrap injected before every [board.ui] action script.
const String kUiViewScriptBootstrap = r'''
var yoloit = {
  get storage() { return storage; },
  set: function(key, value) { storage[key] = value; return value; },
  // Read by element id (textField id/storageKey) or any storage key.
  get: function(key, fallback) {
    return storage[key] !== undefined && storage[key] !== null ? storage[key] : fallback;
  },
  el: function(id, fallback) { return yoloit.get(id, fallback); },
  toggle: function(key) {
    storage[key] = !storage[key];
    return storage[key];
  },
  merge: function(patch) {
    if (patch && typeof patch === 'object') {
      for (var k in patch) { storage[k] = patch[k]; }
    }
    return storage;
  },
  inc: function(key, delta) {
    var step = delta === undefined ? 1 : Number(delta);
    storage[key] = (Number(storage[key]) || 0) + step;
    return storage[key];
  },
  field: function(key, fallback) {
    if (payload && payload.key === key && payload.value !== undefined) {
      return payload.value;
    }
    return yoloit.get(key, fallback);
  },
  toast: function(message) { storage._toast = String(message); },
  clearToast: function() { delete storage._toast; },
  log: function() {
    var line = Array.prototype.slice.call(arguments).map(String).join(' ');
    storage._lastLog = line;
    if (!storage._logs) storage._logs = [];
    storage._logs.push(line);
    if (storage._logs.length > 50) storage._logs.shift();
  }
};
var ui = yoloit;
''';
