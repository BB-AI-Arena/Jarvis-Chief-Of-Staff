import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

// Original procedural android geometry; no downloaded face or actor likeness.
const gaussian=(x,y,cx,cy,wx,wy)=>Math.exp(-(((x-cx)/wx)**2)-(((y-cy)/wy)**2));
function relief(x,y){
  let z=0;
  for(const sign of [-1,1]){
    z-=.14*gaussian(x,y,sign*.29,.25,.18,.14); // orbital sockets
    z+=.09*gaussian(x,y,sign*.29,.43,.25,.07); // brow ridge
    z+=.075*gaussian(x,y,sign*.43,-.04,.2,.23); // cheekbone
    z+=.055*gaussian(x,y,sign*.12,-.16,.07,.06); // nose wings
  }
  z+=.25*gaussian(x,y,0,.11,.09,.36);
  z+=.17*gaussian(x,y,0,-.095,.12,.12);
  z+=.055*gaussian(x,y,0,-.33,.27,.055);
  z+=.06*gaussian(x,y,0,-.43,.25,.07);
  z-=.045*gaussian(x,y,0,-.38,.27,.024);
  z+=.09*gaussian(x,y,0,-.72,.29,.21);
  return z;
}
const jawScale=y=>y<-.2?1-.23*Math.min(1,(-y-.2)/1.02):1;
function headPoint(x,y,z){
  const yy=y*1.22;
  const xx=x*.76*jawScale(yy);
  return new THREE.Vector3(xx,yy,z*.65+(z>0?relief(xx,yy)*Math.min(1,z*4):0));
}
function front(x,y){const rawX=x/(.76*jawScale(y));return Math.sqrt(Math.max(0,1-rawX*rawX-(y/1.22)**2))*.65+relief(x,y)}
function headGeometry(){
  const g=new THREE.SphereGeometry(1,112,96);
  const p=g.attributes.position;
  for(let i=0;i<p.count;i++){const v=headPoint(p.getX(i),p.getY(i),p.getZ(i));p.setXYZ(i,v.x,v.y,v.z)}
  g.computeVertexNormals();return g;
}
function glowTexture(){
  const c=document.createElement('canvas');c.width=c.height=128;
  const ctx=c.getContext('2d'),g=ctx.createRadialGradient(64,64,0,64,64,64);
  g.addColorStop(0,'#c5faff');g.addColorStop(.12,'#55dcffb0');g.addColorStop(.45,'#32c5ff30');g.addColorStop(1,'#2baaff00');
  ctx.fillStyle=g;ctx.fillRect(0,0,128,128);return new THREE.CanvasTexture(c);
}
class Presence {
  constructor(canvas,small,readState){
    this.canvas=canvas;this.small=small;this.readState=readState;this.blend=0;this.level=0;this.mouth=[0,0,0,0];this.last=0;this.disposed=false;
    this.renderer=new THREE.WebGLRenderer({canvas,alpha:true,antialias:!small,powerPreference:'low-power'});
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio,small?1.4:1.8));
    this.renderer.setClearColor(0x000000,0);this.renderer.toneMapping=THREE.ACESFilmicToneMapping;this.renderer.toneMappingExposure=1.35;
    this.scene=new THREE.Scene();this.camera=new THREE.PerspectiveCamera(33,1,.1,30);this.camera.position.set(0,.05,5.7);this.camera.lookAt(0,-.08,0);
    const pmrem=new THREE.PMREMGenerator(this.renderer),room=new RoomEnvironment();
    this.environment=pmrem.fromScene(room,.04);this.scene.environment=this.environment.texture;room.dispose();pmrem.dispose();
    this.scene.add(new THREE.HemisphereLight(0x87cfff,0x020914,1.2));
    const light=(color,intensity,x,y,z)=>{const l=new THREE.DirectionalLight(color,intensity);l.position.set(x,y,z);this.scene.add(l)};
    light(0xd6ecff,4,-2,3,4);light(0x31b8ff,5,3,1,-2);light(0x768eff,2,-3,-.3,1);light(0xffffff,1.4,0,-2,3);
    this.head=new THREE.Group();this.head.position.y=.03;this.scene.add(this.head);this.faceMaterials=[];
    const metal=new THREE.MeshPhysicalMaterial({color:0x355b73,metalness:.88,roughness:.27,clearcoat:.85,clearcoatRoughness:.15,emissive:0x052133,emissiveIntensity:.24,transparent:true,opacity:0});
    this.faceMaterials.push(metal);
    this.head.add(new THREE.Mesh(headGeometry(),metal));
    const dark=new THREE.MeshStandardMaterial({color:0x071523,metalness:.85,roughness:.26,transparent:true,opacity:0});this.faceMaterials.push(dark);
    const luminous=new THREE.MeshBasicMaterial({color:0x9ef4ff,transparent:true,opacity:0});this.faceMaterials.push(luminous);this.eyeMaterial=luminous;
    const glowMap=glowTexture();
    for(const sign of [-1,1]){
      const x=sign*.29,y=.25,z=front(x,y);
      const socket=new THREE.Mesh(new THREE.SphereGeometry(1,32,16),dark);socket.scale.set(.165,.076,.035);socket.position.set(x,y,z+.008);this.head.add(socket);
      const eye=new THREE.Mesh(new THREE.SphereGeometry(1,32,16),luminous);eye.scale.set(.118,.031,.024);eye.position.set(x,y,z+.036);this.head.add(eye);
      const pupil=new THREE.Mesh(new THREE.SphereGeometry(.024,20,12),luminous);pupil.position.set(x,y,z+.061);this.head.add(pupil);
      const glowMat=new THREE.SpriteMaterial({map:glowMap,color:0x4ad5ff,transparent:true,opacity:0,depthWrite:false,blending:THREE.AdditiveBlending});this.faceMaterials.push(glowMat);
      const glow=new THREE.Sprite(glowMat);glow.scale.set(.48,.24,1);glow.position.set(x,y,z+.08);this.head.add(glow);
      const ear=new THREE.Mesh(new THREE.CylinderGeometry(.145,.145,.075,40),metal);ear.rotation.z=Math.PI/2;ear.position.set(sign*.735,.025,0);this.head.add(ear);
      const earLight=new THREE.Mesh(new THREE.TorusGeometry(.1,.009,8,40),luminous);earLight.rotation.y=Math.PI/2;earLight.position.set(sign*.78,.025,0);this.head.add(earLight);
    }
    this.jaw=new THREE.Group();this.head.add(this.jaw);
    const mouthPoints=[];for(let i=0;i<=40;i++){const x=(i/40-.5)*.43,y=-.38-.018*Math.cos(x*9);mouthPoints.push(new THREE.Vector3(x,y,front(x,y)+.015))}
    const mouth=new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(mouthPoints),40,.014,6,false),dark);this.jaw.add(mouth);
    const lowerLip=new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(mouthPoints.map(p=>new THREE.Vector3(p.x,p.y-.037,p.z+.005))),40,.0035,6,false),luminous);this.jaw.add(lowerLip);
    this.neck=new THREE.Mesh(new THREE.CylinderGeometry(.24,.29,.48,32),dark);this.neck.position.set(0,-1.29,-.1);this.head.add(this.neck);
    const circuitMat=new THREE.LineBasicMaterial({color:0x4faed0,transparent:true,opacity:0});this.faceMaterials.push(circuitMat);
    const seamMat=new THREE.LineBasicMaterial({color:0x061423,transparent:true,opacity:0});this.faceMaterials.push(seamMat);
    const trace=(coords,material)=>{
      const pts=coords.map(([x,y])=>new THREE.Vector3(x,y,front(x,y)+.013));
      const geometry=new THREE.BufferGeometry().setFromPoints(new THREE.CatmullRomCurve3(pts).getPoints(65));
      this.head.add(new THREE.Line(geometry,material));
    };
    for(const sign of [-1,1]){
      trace([[sign*.57,.62],[sign*.49,.79],[sign*.25,.97],[sign*.13,.99]],seamMat);
      trace([[sign*.58,.29],[sign*.61,.05],[sign*.51,-.19],[sign*.39,-.58],[sign*.26,-.82]],circuitMat);
      trace([[sign*.60,.24],[sign*.47,.47],[sign*.18,.5]],circuitMat);
      trace([[sign*.56,-.27],[sign*.44,-.55],[sign*.35,-.70]],seamMat);
    }
    trace([[0,.55],[0,.82],[0,1.04]],circuitMat);
    // Preserve the exact supplied portrait. A subdivided relief mesh gives it
    // modest parallax; this is not a fabricated full-head reconstruction.
    if(window.JARVIS_PORTRAIT){
      this.head.clear();
      const geometry=new THREE.PlaneGeometry(2.85,2.85,144,144),p=geometry.attributes.position;
      for(let i=0;i<p.count;i++){
        const u=geometry.attributes.uv.getX(i),v=geometry.attributes.uv.getY(i);
        const g=(cx,cy,wx,wy)=>Math.exp(-(((u-cx)/wx)**2)-(((v-cy)/wy)**2));
        const depth=.31*g(.5,.59,.28,.38)+.18*g(.5,.48,.065,.1)+.08*g(.31,.52,.12,.12)+.08*g(.69,.52,.12,.12)-.055*g(.38,.615,.05,.035)-.055*g(.624,.615,.05,.035)+.10*g(.5,.12,.18,.2);
        p.setZ(i,depth-.12);
      }
      geometry.computeVertexNormals();
      const texture=new THREE.TextureLoader().load(window.JARVIS_PORTRAIT,()=>{this.dirty=true});texture.colorSpace=THREE.SRGBColorSpace;
      this.portraitMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:true,toneMapped:false,
        uniforms:{portrait:{value:texture},fade:{value:0},energy:{value:0},mouthOpen:{value:0},mouthRound:{value:0},mouthWide:{value:0},mouthPress:{value:0},time:{value:0},processing:{value:0}},
        vertexShader:'varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}',
        fragmentShader:`uniform sampler2D portrait;uniform float fade;uniform float energy;uniform float mouthOpen;uniform float mouthRound;uniform float mouthWide;uniform float mouthPress;uniform float time;uniform float processing;varying vec2 vUv;
          float eye(vec2 p){vec2 d=(vUv-p)/vec2(.019,.016);return exp(-dot(d,d)*1.5);}
          void main(){vec2 uv=vUv;
          float width=.095*(1.-mouthRound*.25+mouthWide*.12);
          float shape=max(0.,1.-pow((uv.x-.5)/width,2.));
          float mouth=exp(-pow((uv.x-.5)/.12,4.)-pow((uv.y-.362)/.07,4.));
          float opening=mouthOpen*.035*(1.-mouthPress*.8)*shape;
          float lower=1.-smoothstep(.358,.367,uv.y);
          uv.y+=opening*mouth*(lower*.88-(1.-lower)*.12);
          // Pull the lower jaw along with the lower lip; preserve the upper face.
          float chin=exp(-pow((uv.x-.5)/.17,4.)-pow((uv.y-.27)/.08,4.));
          uv.y+=chin*mouthOpen*.014;
          float cheek=exp(-pow((abs(uv.x-.5)-.12)/.055,2.)-pow((uv.y-.39)/.075,2.));
          uv.y+=cheek*mouthOpen*.004;
          uv.x+=(uv.x-.5)*cheek*mouthWide*.025;
          uv.x+=(uv.x-.5)*mouth*mouthRound*.14;
          uv.x-=(uv.x-.5)*mouth*mouthWide*.07;
          vec3 c=texture2D(portrait,uv).rgb;
          float gap=(1.-smoothstep(opening*.65,opening+.0004,abs(vUv.y-(.362-opening*.32))))*mouth*step(.0006,opening);
          c=mix(c,vec3(.003,.009,.014),gap*.94);
          float glow=eye(vec2(.38,.615))+eye(vec2(.624,.615));float pulse=processing*(.5+.5*sin(time*4.4));
          c*=1.+glow*pulse*.7;c+=vec3(.02,.16,.22)*glow*(.25+pulse*1.5+energy*.35);
          vec2 dl=(vUv-vec2(.38,.615))/vec2(.05,.04),dr=(vUv-vec2(.624,.615))/vec2(.05,.04);float halo=exp(-dot(dl,dl)*2.)+exp(-dot(dr,dr)*2.);
          c+=vec3(.0,.025,.04)*halo*pulse;float edge=smoothstep(0.,.07,vUv.x)*smoothstep(0.,.07,1.-vUv.x)*smoothstep(0.,.05,vUv.y)*smoothstep(0.,.05,1.-vUv.y);
          gl_FragColor=vec4(c,edge*fade);
          #include <colorspace_fragment>
          }`});
      this.head.add(new THREE.Mesh(geometry,this.portraitMaterial));
      this.head.position.y=.02;
    }
    const count=small?700:2400,positions=new Float32Array(count*3),targets=new Float32Array(count*3),colors=new Float32Array(count*3);
    for(let i=0;i<count;i++){
      const y=1-2*(i+.5)/count,angle=i*2.399963229728653,r=Math.sqrt(1-y*y),x=Math.cos(angle)*r,z=Math.sin(angle)*r;
      positions.set([x*.96,y*.96,z*.96],i*3);const v=headPoint(x,y,z);targets.set([v.x*1.004,v.y*1.004,v.z*1.007],i*3);
      colors.set([.22+(z+1)*.14,.65+(z+1)*.13,1],i*3);
    }
    const geometry=new THREE.BufferGeometry();geometry.setAttribute('position',new THREE.BufferAttribute(positions,3));geometry.setAttribute('color',new THREE.BufferAttribute(colors,3));geometry.morphAttributes.position=[new THREE.BufferAttribute(targets,3)];
    this.particles=new THREE.Points(geometry,new THREE.PointsMaterial({size:small?.022:.015,vertexColors:true,transparent:true,opacity:.88,blending:THREE.AdditiveBlending,depthWrite:false}));this.scene.add(this.particles);
    this.orb=new THREE.Mesh(new THREE.SphereGeometry(.96,48,32),new THREE.MeshPhysicalMaterial({color:0x126488,metalness:.72,roughness:.22,transparent:true,opacity:.32,emissive:0x0875a5,emissiveIntensity:.24,clearcoat:1}));this.scene.add(this.orb);
    const orbitGeometry=new THREE.TorusGeometry(1.25,.0025,4,120);this.orbit=new THREE.Mesh(orbitGeometry,new THREE.MeshBasicMaterial({color:0x2e819f,transparent:true,opacity:.3}));this.orbit.rotation.x=1.25;this.orbit.rotation.z=-.25;this.scene.add(this.orbit);
    this.observer=new ResizeObserver(()=>this.resize());this.observer.observe(canvas);this.resize();
    this.animate=this.animate.bind(this);requestAnimationFrame(this.animate);
  }
  resize(){const rect=this.canvas.getBoundingClientRect();if(!rect.width||!rect.height)return;this.renderer.setSize(rect.width,rect.height,false);this.camera.aspect=rect.width/rect.height;this.camera.updateProjectionMatrix();this.dirty=true}
  animate(now){
    if(this.disposed)return;requestAnimationFrame(this.animate);
    if(document.hidden||!this.canvas.getClientRects().length||now-this.last<(this.small?42:33))return;
    const s=this.readState(),target=s.active?1:0,changed=Math.abs(target-this.blend)>.001;
    if(!s.motion&&!changed&&!this.dirty&&this.wasActive===s.active&&s.state!=='speaking'&&this.level<.005)return;
    this.last=now;this.dirty=false;this.wasActive=s.active;this.blend+=(target-this.blend)*.16;if(Math.abs(target-this.blend)<.001)this.blend=target;
    const t=this.blend,time=s.motion?now*.00035:0;const wanted=Math.min(1,s.level||0);this.level+=(wanted-this.level)*(wanted>this.level?.5:.3);
    this.head.visible=t>.005;for(const material of this.faceMaterials){material.opacity=t*(material.isSpriteMaterial?.32:material.isLineBasicMaterial?.42:1)}
    this.head.rotation.set(-.025+Math.sin(time*.55)*.018,.10+Math.sin(time*.48)*.045,Math.sin(time*.31)*.007);
    const goal=s.state==='speaking'?(s.mouth||[this.level*.65,0,0,0]):[0,0,0,0];
    for(let i=0;i<4;i++){const response=[.5,.6,.55,.8][i];this.mouth[i]+=(goal[i]-this.mouth[i])*response;}
    if(this.portraitMaterial){this.portraitMaterial.uniforms.mouthOpen.value=this.mouth[0];this.portraitMaterial.uniforms.mouthRound.value=this.mouth[1];this.portraitMaterial.uniforms.mouthWide.value=this.mouth[2];this.portraitMaterial.uniforms.mouthPress.value=this.mouth[3];this.portraitMaterial.uniforms.fade.value=t;this.portraitMaterial.uniforms.energy.value=this.level;this.portraitMaterial.uniforms.time.value=now*.001;this.portraitMaterial.uniforms.processing.value=(s.working||s.state==='thinking'||s.state==='synthesizing')?1:0;this.head.rotation.y*=.35;this.head.rotation.x*=.5}
    if(s.state==='speaking'){
      const emphasis=this.mouth[0]*this.level;
      this.head.rotation.x+=emphasis*.035;
      this.head.rotation.y+=this.mouth[1]*.009;
      this.head.rotation.z+=this.mouth[2]*.004;
    }
    this.particles.morphTargetInfluences[0]=t;this.particles.rotation.copy(this.head.rotation);this.particles.rotation.y+=(1-t)*time*.27;this.particles.material.opacity=.85*(1-t);
    this.orb.visible=t<.995;this.orb.material.opacity=.32*(1-t);this.orb.rotation.y=time*.27;
    this.orbit.visible=t<.995;this.orbit.material.depthWrite=false;this.orbit.material.opacity=.28*(1-t);this.orbit.rotation.z=-.25+time*.05;
    const talking=s.state==='speaking';const amount=talking?this.level:0;this.jaw.position.y=-amount*.045;this.jaw.scale.y=1+amount*.12;
    this.eyeMaterial.color.setHex(s.state==='thinking'?0x8ccfff:0xa9f4ff);this.eyeMaterial.opacity=t*(.88+Math.sin(time*1.1)*.08);
    this.renderer.render(this.scene,this.camera);
  }
}
window.JarvisPresence=Presence;
