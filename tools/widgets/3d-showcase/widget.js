// 3D Showcase — procedural primitives powered by flutter_cube
(function() {
  var sceneId = 'demo-' + (jsr.instanceId || 'demo');
  var modelId = 'shape';
  var shape = 'cube';
  var color = '#3b82f6';
  var rotating = true;
  var speed = 0.5;
  var palette = ['#3b82f6', '#ef4444', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'];

  function init() {
    jsr.scene3d.create(sceneId, {
      camera: { position: [0, 0, -8], target: [0, 0, 0], fov: 60 },
      // Higher ambient light makes flat shading less harsh; flutter_cube does
      // not cast real shadows, so a strong ambient term avoids "glitchy" dark
      // faces on the cube/torus/city.
      light: { position: [5, 8, 5], color: '#ffffff', ambient: 0.4, diffuse: 0.7 }
    });
    addModel();
    if (rotating) jsr.scene3d.playAnimation(sceneId, modelId, { axis: 'y', speed: speed });
    render();
  }

  function addModel() {
    var scale = [2, 2, 2];
    if (shape === 'torus' || shape === 'city') {
      scale = [1.4, 1.4, 1.4];
    }
    jsr.scene3d.addModel(sceneId, {
      modelId: modelId,
      primitive: shape,
      color: color,
      scale: scale
    });
  }

  function setShape(next) {
    shape = next;
    jsr.scene3d.removeModel(sceneId, modelId);
    addModel();
    if (rotating) jsr.scene3d.playAnimation(sceneId, modelId, { axis: 'y', speed: speed });
    render();
  }

  function setColor(next) {
    color = next;
    jsr.scene3d.removeModel(sceneId, modelId);
    addModel();
    if (rotating) jsr.scene3d.playAnimation(sceneId, modelId, { axis: 'y', speed: speed });
    render();
  }

  function toggleRotation() {
    rotating = !rotating;
    if (rotating) {
      jsr.scene3d.playAnimation(sceneId, modelId, { axis: 'y', speed: speed });
    } else {
      jsr.scene3d.stopAnimation(sceneId, modelId);
    }
    render();
  }

  function setSpeed(next) {
    speed = next;
    if (rotating) {
      jsr.scene3d.playAnimation(sceneId, modelId, { axis: 'y', speed: speed });
    }
    render();
  }

  function shapeButton(label, value) {
    var active = shape === value;
    return {
      type: 'expanded',
      child: {
        type: 'inkWell',
        onTap: 'shape_' + value,
        borderRadius: 8,
        child: {
          type: 'container',
          padding: [8, 8, 8, 8],
          decoration: {
            color: active ? jsr.theme.accent : jsr.theme.surface,
            borderRadius: 8,
            borderColor: jsr.theme.border,
            borderWidth: 1
          },
          child: {
            type: 'center',
            child: {
              type: 'text',
              data: label,
              style: {
                color: active ? '#ffffff' : jsr.theme.text,
                fontSize: 12,
                fontWeight: active ? 'w600' : 'w400'
              }
            }
          }
        }
      }
    };
  }

  function colorDot(c) {
    var active = color === c;
    return {
      type: 'inkWell',
      onTap: 'color_' + c,
      borderRadius: 18,
      child: {
        type: 'container',
        width: 28,
        height: 28,
        margin: [4, 4, 4, 4],
        decoration: {
          color: c,
          borderRadius: 14,
          borderColor: active ? jsr.theme.text : 'transparent',
          borderWidth: active ? 2 : 0
        }
      }
    };
  }

  function render() {
    jsr.render({
      type: 'column',
      crossAxisAlignment: 'stretch',
      children: [
        {
          type: 'expanded',
          child: {
            type: 'scene3d',
            id: sceneId,
            width: 320,
            height: 320
          }
        },
        {
          type: 'container',
          color: jsr.theme.surface,
          padding: [12, 12, 12, 12],
          child: {
            type: 'column',
            crossAxisAlignment: 'stretch',
            mainAxisSize: 'min',
            children: [
              {
                type: 'row',
                children: [
                  shapeButton('Cube', 'cube'),
                  { type: 'sizedBox', width: 8 },
                  shapeButton('Sphere', 'sphere'),
                  { type: 'sizedBox', width: 8 },
                  shapeButton('Torus', 'torus'),
                  { type: 'sizedBox', width: 8 },
                  shapeButton('City', 'city')
                ]
              },
              { type: 'sizedBox', height: 12 },
              {
                type: 'row',
                mainAxisAlignment: 'center',
                children: palette.map(colorDot)
              },
              { type: 'sizedBox', height: 12 },
              {
                type: 'row',
                crossAxisAlignment: 'center',
                children: [
                  {
                    type: 'expanded',
                    child: {
                      type: 'column',
                      crossAxisAlignment: 'stretch',
                      mainAxisSize: 'min',
                      children: [
                        {
                          type: 'text',
                          data: 'Rotation speed: ' + speed.toFixed(1) + 'x',
                          style: { fontSize: 12, color: jsr.theme.text }
                        },
                        {
                          type: 'slider',
                          value: speed,
                          min: 0,
                          max: 3,
                          divisions: 30,
                          onChanged: 'set_speed'
                        }
                      ]
                    }
                  },
                  { type: 'sizedBox', width: 8 },
                  {
                    type: 'button',
                    text: rotating ? '⏸ Pause' : '▶ Rotate',
                    onTap: 'toggle_rotation'
                  }
                ]
              }
            ]
          }
        }
      ]
    });
  }

  function handleEvent(actionId, payload) {
    if (actionId === 'toggle_rotation') {
      toggleRotation();
      return;
    }
    if (actionId === 'set_speed') {
      setSpeed((payload && payload.value) || 0.5);
      return;
    }
    if (actionId.indexOf('shape_') === 0) {
      setShape(actionId.substring(6));
      return;
    }
    if (actionId.indexOf('color_') === 0) {
      setColor(actionId.substring(6));
      return;
    }
  }

  jsr.onEvent(handleEvent);
  jsr.setTitle('🧊 3D Showcase');
  init();
})();
