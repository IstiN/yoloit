/// Shared JavaScript bootstrap injected before a widget's JS code.
///
/// It defines the `yoloit` API, `console`, timers and
/// `requestAnimationFrame`. The runtime must provide a global `sendMessage`
/// function that accepts `(channelName, jsonString)`.
const String kJsWidgetBootstrap = r'''
var __cbs = {};
var __iv_cbs = {};
var __raf_cbs = {};
var __nid = function(){return Math.random().toString(36).slice(2)+Date.now().toString(36);};

var console = {
  log:   function(){sendMessage('__yoloit_log', Array.prototype.slice.call(arguments).join(' '));},
  warn:  function(){sendMessage('__yoloit_log', '[W] '+Array.prototype.slice.call(arguments).join(' '));},
  error: function(){sendMessage('__yoloit_log', '[E] '+Array.prototype.slice.call(arguments).join(' '));}
};

var setTimeout = function(fn,ms){ var id=__nid(); __iv_cbs[id]=function(){fn();clearInterval(id);}; sendMessage('__yoloit_set_interval',JSON.stringify({id:id,ms:ms||0})); return id; };
var clearTimeout = function(id){ sendMessage('__yoloit_clear_interval', String(id)); };
var setInterval = function(fn,ms){ var id=__nid(); __iv_cbs[id]=fn; sendMessage('__yoloit_set_interval',JSON.stringify({id:id,ms:ms||1000})); return id; };
var clearInterval = function(id){ sendMessage('__yoloit_clear_interval', String(id)); delete __iv_cbs[String(id)]; };

var requestAnimationFrame = function(fn){ var id=__nid(); __raf_cbs[id]=fn; sendMessage('__yoloit_raf',JSON.stringify({id:id})); return id; };
var cancelAnimationFrame = function(id){ delete __raf_cbs[String(id)]; sendMessage('__yoloit_caf', String(id)); };

var yoloit = {
  render: function(tree){ sendMessage('__yoloit_render', JSON.stringify(tree)); },

  fetchJson: function(url,opts){
    return new Promise(function(resolve,reject){
      var id=__nid();
      __cbs[id]=function(r){if(r&&r.__error)reject(new Error(r.__error));else resolve(r);};
      sendMessage('__yoloit_fetch', JSON.stringify({id:id,url:url,method:(opts&&opts.method)||'GET',headers:(opts&&opts.headers)||{}}));
    });
  },

  exec: function(cmd){
    return new Promise(function(resolve,reject){
      var id=__nid();
      __cbs[id]=function(r){if(r&&r.__error)reject(new Error(r.__error));else resolve(r);};
      sendMessage('__yoloit_exec', JSON.stringify({id:id,cmd:cmd}));
    });
  },

  storage:{
    _c:{},
    get:function(key){
      if(key in this._c)return Promise.resolve(this._c[key]);
      var self=this;
      return new Promise(function(resolve){
        var id=__nid();
        __cbs[id]=function(v){self._c[key]=v;resolve(v);};
        sendMessage('__yoloit_storage_get', JSON.stringify({id:id,key:key}));
      });
    },
    set:function(key,val){
      this._c[key]=val;
      sendMessage('__yoloit_storage_set', JSON.stringify({key:key,value:val}));
      return Promise.resolve();
    }
  },

  panel:{setTitle:function(t){sendMessage('__yoloit_set_title', String(t));}},

  // Structured state for CLI (yoloit app:state)
  exportState:function(obj){sendMessage('__yoloit_export_state', JSON.stringify(obj||{}));},

  // Event handler registration — called from IIFE widgets:
  //   yoloit.onEvent(function handleEvent(actionId, payload) { ... });
  _handler: null,
  onEvent: function(fn){ yoloit._handler = fn; },

  // Theme — updated by Dart when the user switches themes
  theme: {isDark:true,bg:'#0f172a',surface:'#1e293b',border:'#334155',accent:'#818cf8',text:'#f1f5f9',muted:'#64748b'},
  _onThemeChange: null,
  onThemeChange: function(fn){ yoloit._onThemeChange = fn; },

  // Encrypted secure storage — sandboxed per widget ID
  secrets:{
    get:function(key){
      return new Promise(function(resolve){
        var id=__nid();
        __cbs[id]=function(v){resolve(v);};
        sendMessage('__yoloit_secrets_get', JSON.stringify({id:id,key:key}));
      });
    },
    set:function(key,val){
      return new Promise(function(resolve){
        var id=__nid();
        __cbs[id]=function(ok){resolve(ok);};
        sendMessage('__yoloit_secrets_set', JSON.stringify({id:id,key:key,value:val}));
      });
    },
    delete:function(key){
      return new Promise(function(resolve){
        var id=__nid();
        __cbs[id]=function(ok){resolve(ok);};
        sendMessage('__yoloit_secrets_set', JSON.stringify({id:id,key:key,value:null}));
      });
    }
  },

  showError:function(msg){
    yoloit.render({type:'center',child:{type:'padding',padding:[16,16,16,16],child:{
      type:'column',mainAxisSize:'min',children:[
        {type:'text',data:'\u26a0\ufe0f',style:{fontSize:28}},
        {type:'sizedBox',height:8},
        {type:'text',data:String(msg),style:{color:'#ef4444',fontSize:13,textAlign:'center'}}
      ]
    }}});
  },

  loadAsset: function(path) {
    return new Promise(function(resolve) {
      var id = __nid();
      __cbs[id] = function(v) { resolve(v); };
      sendMessage('__yoloit_load_asset', JSON.stringify({id: id, path: path}));
    });
  }
};
''';
