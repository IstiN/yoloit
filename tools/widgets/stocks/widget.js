// Stocks widget — Yahoo Finance summary API (via Dart fetch, no CORS)
(function() {
  var DEFAULT = ['AAPL','MSFT','GOOGL','NVDA','TSLA'];
  var symbols = DEFAULT;

  function fmt(n, sign) {
    var s = n >= 0 ? (sign?'+':'') : '-';
    return s + Math.abs(n).toFixed(2);
  }

  async function load() {
    yoloit.render({type:'center',child:{type:'circularProgressIndicator',size:24}});
    try {
      var qs = encodeURIComponent(symbols.join(','));
      var url = 'https://query1.finance.yahoo.com/v7/finance/quote?symbols='+qs+'&fields=regularMarketPrice,regularMarketChangePercent,regularMarketChange,shortName';
      var data = await yoloit.fetchJson(url);
      var quotes = data.quoteResponse.result || [];
      var now = new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'});

      var rows = quotes.map(function(q) {
        var chg = q.regularMarketChangePercent || 0;
        var chgAbs = q.regularMarketChange || 0;
        var chgColor = chg >= 0 ? '#4ade80' : '#f87171';
        var bgColor = chg >= 0 ? '#052e16' : '#2d0a0a';
        return {
          type:'container',
          margin:[0,0,0,6],
          decoration:{color:'#1e293b',borderRadius:8,borderColor:'#334155',borderWidth:1},
          padding:[12,10,12,10],
          child:{type:'row',crossAxisAlignment:'center',children:[
            {type:'expanded',child:{type:'column',crossAxisAlignment:'start',children:[
              {type:'text',data:q.symbol,style:{color:'#e2e8f0',fontWeight:'w700',fontSize:14}},
              {type:'text',data:(q.shortName||'').substring(0,22),
               style:{color:'#475569',fontSize:10},maxLines:1,overflow:'ellipsis'},
            ]}},
            {type:'column',crossAxisAlignment:'end',mainAxisSize:'min',children:[
              {type:'text',data:'$'+(q.regularMarketPrice||0).toFixed(2),
               style:{color:'#f1f5f9',fontWeight:'w700',fontSize:14}},
              {type:'container',
               decoration:{color:bgColor,borderRadius:4},
               padding:[3,2,3,2],
               child:{type:'text',
                 data:fmt(chgAbs,true)+' ('+fmt(chg,true)+'%)',
                 style:{color:chgColor,fontSize:10},
               }},
            ]},
          ]},
        };
      });

      if (rows.length === 0) {
        yoloit.showError('No data returned for: '+symbols.join(', '));
        return;
      }

      yoloit.render({
        type:'column',crossAxisAlignment:'stretch',
        children:[
          {type:'padding',padding:[12,12,12,4],child:{
            type:'column',crossAxisAlignment:'stretch',children:rows,
          }},
          {type:'padding',padding:[12,4,12,8],child:{type:'row',
            mainAxisAlignment:'spaceBetween',
            children:[
              {type:'textButton',text:'Edit symbols',onTap:'edit_symbols'},
              {type:'textButton',text:'Refresh',onTap:'refresh'},
            ]
          }},
          {type:'padding',padding:[0,0,12,8],child:{
            type:'text',data:'Yahoo Finance · '+now,
            style:{color:'#334155',fontSize:10,textAlign:'right'},
          }},
        ]
      });
    } catch(e) {
      yoloit.showError('Could not load stocks:\n'+e.message);
    }
  }

  function handleEvent(actionId, payload) {
    if (actionId === 'refresh') { load(); return; }
    if (actionId === 'edit_symbols') {
      // Cycle to next preset set
      var presets = [
        ['AAPL','MSFT','GOOGL','NVDA','TSLA'],
        ['META','AMZN','NFLX','BABA','V'],
        ['BRK-B','JPM','JNJ','PFE','KO'],
      ];
      var cur = JSON.stringify(symbols);
      var idx = presets.findIndex(function(p){return JSON.stringify(p)===cur;});
      symbols = presets[(idx+1)%presets.length];
      yoloit.storage.set('symbols', symbols);
      load();
    }
  }

  yoloit.panel.setTitle('Stocks');
  yoloit.storage.get('symbols').then(function(saved){
    if (saved && Array.isArray(saved)) symbols = saved;
    load();
    setInterval(load, 2*60*1000);
  });
})();
