// 3D GLB Showcase — high-quality model viewer powered by flame_3d.
(function() {
  var sceneId = 'glb-demo';
  var modelId = 'helmet';
  var rotating = true;
  var speed = 0.5;

  function init() {
    jsr.scene3d.create(sceneId, {
      engine: 'flame',
      camera: { position: [0, 0, 8], target: [0, 0, 0], fov: 60 },
      light: { position: [5, 8, 5], ambient: 5.0, diffuse: 2.0 }
    });
    jsr.scene3d.addModel(sceneId, {
      modelId: modelId,
      src: 'models/DamagedHelmet.glb',
      scale: [2, 2, 2]
    });
    if (rotating) {
      jsr.scene3d.playAnimation(sceneId, modelId, { axis: 'y', speed: speed });
    }
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
  }

  jsr.onEvent(handleEvent);
  jsr.setTitle('🧊 GLB Showcase');
  init();
})();
