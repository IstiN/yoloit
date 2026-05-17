// Weather widget — native Flutter UI via JSON tree
// Uses wttr.in free API (fetched through Dart, no CORS)
(function() {
  var city = 'London';

  function iconForDesc(desc) {
    var d = desc.toLowerCase();
    if (d.indexOf('sun') >= 0 || d.indexOf('clear') >= 0) return '☀️';
    if (d.indexOf('part') >= 0) return '⛅';
    if (d.indexOf('cloud') >= 0 || d.indexOf('overcast') >= 0) return '☁️';
    if (d.indexOf('rain') >= 0 || d.indexOf('drizzle') >= 0) return '🌧️';
    if (d.indexOf('snow') >= 0 || d.indexOf('blizzard') >= 0) return '❄️';
    if (d.indexOf('thunder') >= 0) return '⛈️';
    if (d.indexOf('fog') >= 0 || d.indexOf('mist') >= 0) return '🌫️';
    return '🌡️';
  }

  async function load() {
    yoloit.render({type:'center',child:{type:'circularProgressIndicator',size:24}});
    try {
      var url = 'https://wttr.in/' + encodeURIComponent(city) + '?format=j1';
      var data = await yoloit.fetchJson(url);
      var cur = data.current_condition[0];
      var area = data.nearest_area[0];
      var areaName = area.areaName[0].value;
      var country = area.country[0].value;
      var icon = iconForDesc(cur.weatherDesc[0].value);

      yoloit.panel.setTitle('Weather — ' + areaName);
      yoloit.render({
        type: 'column',
        crossAxisAlignment: 'stretch',
        children: [
          // Header
          {type:'container', decoration:{color:'#0f172a', borderRadius:0},
           padding:[16,20,16,16],
           child:{type:'column',crossAxisAlignment:'center',children:[
            {type:'text',data:icon,style:{fontSize:52}},
            {type:'sizedBox',height:4},
            {type:'text',data:areaName+', '+country,
             style:{color:'#94a3b8',fontSize:12,textAlign:'center'}},
            {type:'sizedBox',height:6},
            {type:'text',data:cur.temp_C+'°C',
             style:{fontSize:40,fontWeight:'w700',color:'#f1f5f9',textAlign:'center'}},
            {type:'text',data:cur.weatherDesc[0].value,
             style:{color:'#cbd5e1',fontSize:13,textAlign:'center'}},
          ]}},
          // Stats row
          {type:'padding',padding:[12,12,12,8],child:{type:'row',
            mainAxisAlignment:'spaceAround',
            children:[
              _stat('💧','Humidity',cur.humidity+'%'),
              _stat('💨','Wind',cur.windspeedKmph+' km/h'),
              _stat('🌡️','Feels',cur.FeelsLikeC+'°C'),
              _stat('👁️','Vis.',cur.visibility+' km'),
            ]
          }},
          // Change city
          {type:'padding',padding:[12,0,12,12],child:{type:'row',children:[
            {type:'expanded',child:{type:'container',
              decoration:{color:'#1e293b',borderRadius:8,borderColor:'#334155',borderWidth:1},
              padding:[8,8,8,8],
              child:{type:'text',data:'📍 '+city,style:{color:'#94a3b8',fontSize:12}},
            }},
            {type:'sizedBox',width:8},
            {type:'textButton',text:'Change',onTap:'change_city'},
          ]}},
          {type:'padding',padding:[0,0,12,8],child:{
            type:'text',
            data:'via wttr.in',
            style:{color:'#334155',fontSize:10,textAlign:'right'},
          }},
        ]
      });
    } catch(e) {
      yoloit.showError('Could not load weather:\n'+e.message);
    }
  }

  function _stat(icon, label, value) {
    return {type:'column',crossAxisAlignment:'center',mainAxisSize:'min',children:[
      {type:'text',data:icon,style:{fontSize:18}},
      {type:'sizedBox',height:2},
      {type:'text',data:value,style:{color:'#e2e8f0',fontSize:13,fontWeight:'w600'}},
      {type:'text',data:label,style:{color:'#64748b',fontSize:10}},
    ]};
  }

  async function handleEvent(actionId, payload) {
    if (actionId === 'change_city') {
      // cycle through preset cities for demo
      var cities = ['London','New York','Tokyo','Berlin','Sydney','Moscow','Dubai'];
      var idx = cities.indexOf(city);
      city = cities[(idx + 1) % cities.length];
      await yoloit.storage.set('city', city);
      await load();
    }
  }

  yoloit.storage.get('city').then(function(saved) {
    if (saved) city = saved;
    load();
    setInterval(load, 10 * 60 * 1000);
  });
})();
