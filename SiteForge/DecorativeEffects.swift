import Foundation

extension CanonicalFlowGradient {
    static func gradient(on node: DocumentNode) -> CanonicalFillLayer? {
        let layers = DesignInspectorCommandRegistry.resolvedLayers(for: node).filter(\.isEnabled)
        guard layers.count == 1, let layer = layers.first,
              layer.kind == .linearGradient, layer.stops.count <= 64,
              CanonicalImageFill.resolve(node) == nil, LocalColorTokenBinding.id(for: node, target: .fill) == nil else { return nil }
        return layer
    }
}

/// Replaces only its closed namespace and preserves existing property IDs.
/// The normal command registry supplies lock/read-only/history/inverse policy.
enum DecorativeEffectPropertyCommands {
    static func replace(namespace: String, values: [String: PropertyValue], node: DocumentNode,
                        pageID: PageID) -> [DocumentCommand] {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        var commands: [DocumentCommand] = []
        for key in values.keys.sorted() {
            guard let value = values[key] else { continue }
            let old = owned.first { $0.key.rawValue == key }
            if old?.value != value || old?.origin != .authored {
                commands.append(.setProperty(.init(pageID: pageID, nodeID: node.id,
                    property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
            }
        }
        for property in owned where values[property.key.rawValue] == nil {
            commands.append(.removeProperty(.init(pageID: pageID, nodeID: node.id, propertyID: property.id)))
        }
        return commands
    }
}

enum DecorativeEffectEdit: Sendable {
    case flow(CanonicalFlowGradient?)
    case glass(CanonicalGlassSurface?)
}

enum DecorativeEffectCommandRegistry {
    static func prepare(_ edit: DecorativeEffectEdit, identity: DesignInspectorOperationIdentity,
                        orderedNodeIDs: [NodeID], document: CanonicalDocument,
                        context: TransformValidationContext) throws -> PreparedDesignInspectorEdit {
        guard context.isLifecycleAvailable else { throw DesignInspectorError.unavailable("Wait for the document operation before editing effects.") }
        guard identity.documentID == document.id, identity.revision == document.revision,
              identity.pageID == context.activePageID, identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration,
              orderedNodeIDs == context.selectedNodeIDs, !orderedNodeIDs.isEmpty,
              Set(orderedNodeIDs).count == orderedNodeIDs.count,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else { throw DesignInspectorError.stale }
        let namespace: String, values: [String: PropertyValue], kinds: Set<NodeKind>
        switch edit {
        case .flow(let flow):
            guard flow?.isValid ?? true else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalFlowGradient.namespace; values = flow?.properties ?? [:]; kinds = [.frame, .section]
        case .glass(let glass):
            guard glass?.isValid ?? true else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalGlassSurface.namespace; values = glass?.properties ?? [:]; kinds = [.frame, .section, .stack, .grid, .button]
        }
        var applied: [NodeID] = [], skipped: [NodeID] = [], reasons: [NodeID: String] = [:], commands: [DocumentCommand] = []
        for id in orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }), context.availableNodeIDs.contains(id),
                  !node.selectionBooleanProperty("locked"), !node.selectionBooleanProperty("hidden") else { throw DesignInspectorError.stale }
            guard kinds.contains(node.kind) else { skipped.append(id);reasons[id] = "This object kind does not support this effect.";continue }
            if case .flow(let flow) = edit, flow?.enabled == true, CanonicalFlowGradient.gradient(on: node) == nil {
                throw DesignInspectorError.unavailable(CanonicalFlowGradient.unavailableReason)
            }
            applied.append(id)
            commands += DecorativeEffectPropertyCommands.replace(namespace: namespace, values: values, node: node, pageID: page.id)
        }
        guard !applied.isEmpty else { throw DesignInspectorError.unavailable("Select a supported Frame, Section or container to edit this effect.") }
        guard !commands.isEmpty else { throw DesignInspectorError.noChanges }
        let batch = DocumentCommand.batch(commands)
        let availability = CommandRegistry().availability(for: batch, in: document)
        guard availability.isEnabled else { throw DesignInspectorError.unavailable(availability.disabledReason ?? "This effect cannot be applied in the current context.") }
        return .init(applicableNodeIDs: applied, skippedNodeIDs: skipped, skippedReasons: reasons, documentCommand: batch)
    }
}



enum DecorativeEffectRuntime {
    static let javascript = #"""
/* SiteForge local decorative runtime. Configuration is validated build data. */
(() => {
  'use strict';
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const hover = matchMedia('(hover: hover) and (pointer: fine)');
  const active = new Set(), instances = new Map(), failed = new WeakSet();
  let frame = 0, disposed = false, suspended = false;
  const stats = {frames: 0, drawMilliseconds: 0, maximumDrawMilliseconds: 0};
  const vertex = 'attribute vec2 point;varying vec2 uv;void main(){uv=(point+1.0)*0.5;gl_Position=vec4(point,0.0,1.0);}';
  const fragment = `precision highp float;varying vec2 uv;uniform vec2 size;uniform vec2 pointer;
    uniform vec2 pull;uniform float radius;uniform vec2 direction;uniform sampler2D ramp;
    void main(){vec2 p=vec2(uv.x,1.0-uv.y)*size;vec2 d=p-pointer;
      float r=length(d)/radius;float influence=exp(-3.0*r*r)*(1.0-smoothstep(0.75,1.0,r));
      vec2 tangent=vec2(-d.y,d.x)/max(radius,1.0);
      p-=influence*(pull+tangent*(pull.x*d.y-pull.y*d.x)/max(radius,1.0)*0.35);
      float span=abs(direction.x)*size.x+abs(direction.y)*size.y;
      float t=clamp(dot(p-size*0.5,direction)/max(span,1.0)+0.5,0.0,1.0);
      gl_FragColor=texture2D(ramp,vec2(t,0.5));}`;
  const allowed = () => !disposed && !suspended && !document.hidden && !motion.matches && hover.matches;
  const request = item => {if (!allowed() || !item.visible || item.retired) return;
    active.add(item); if (!frame) frame=requestAnimationFrame(tick);};
  function tick(now) {
    frame=0;
    // Read every active element before changing any classes/canvas sizes.
    const measured=Array.from(active).map(item=>[item,item.measure()]);
    for (const [item,geometry] of measured) if (!item.draw(now,geometry)) active.delete(item);
    if (active.size && allowed()) frame=requestAnimationFrame(tick);
  }
  function shader(gl, type, source) {
    const value=gl.createShader(type);gl.shaderSource(value,source);gl.compileShader(value);
    if (!gl.getShaderParameter(value,gl.COMPILE_STATUS)) {gl.deleteShader(value);throw Error('Shader unavailable');}
    return value;
  }
  class Flow {
    constructor(element, config) {
      this.element=element;this.config=config;this.visible=true;this.retired=false;
      this.pointer=null;this.previous=null;this.input=null;this.pull=[0,0];this.last=0;this.lastMove=0;
      this.canvas=document.createElement('canvas');this.canvas.className='sf-flow-canvas';
      this.canvas.setAttribute('aria-hidden','true');this.canvas.hidden=true;
      this.shaders=[];
      try {
      const gl=this.gl=this.canvas.getContext('webgl',{alpha:true,antialias:false,premultipliedAlpha:true,depth:false,stencil:false,preserveDrawingBuffer:false});
      if (!gl) throw Error('WebGL unavailable');
      this.program=gl.createProgram();this.shaders.push(shader(gl,gl.VERTEX_SHADER,vertex));this.shaders.push(shader(gl,gl.FRAGMENT_SHADER,fragment));
      this.shaders.forEach(s=>gl.attachShader(this.program,s));gl.linkProgram(this.program);
      if (!gl.getProgramParameter(this.program,gl.LINK_STATUS)) throw Error('Program unavailable');
      gl.useProgram(this.program);
      this.buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
      const location=gl.getAttribLocation(this.program,'point');gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,2,gl.FLOAT,false,0,0);
      this.uniform={};for(const name of ['size','pointer','pull','radius','direction','ramp'])this.uniform[name]=gl.getUniformLocation(this.program,name);
      const ramp=document.createElement('canvas');ramp.width=1024;ramp.height=1;
      const context=ramp.getContext('2d'), pixels=context.createImageData(1024,1);
      // Explicit premultiplied sRGB interpolation, matching the authored CSS
      // gradient even when transparent endpoints have different RGB values.
      const stops=config.stops.map((s,i)=>({...s,index:i})).sort((a,b)=>a.position-b.position||a.index-b.index);
      for(let x=0;x<1024;x++){
        const t=x/1023;let right=stops.findIndex(s=>s.position>t),a,b;
        if(right===0){a=b=stops[0];}else if(right<0){a=b=stops[stops.length-1];}else{a=stops[right-1];b=stops[right];}
        const f=a===b?0:(t-a.position)/(b.position-a.position),alpha=a.alpha+(b.alpha-a.alpha)*f;
        for(const [i,key] of ['red','green','blue'].entries())pixels.data[x*4+i]=Math.round(255*(alpha>0?(a[key]*a.alpha*(1-f)+b[key]*b.alpha*f)/alpha:0));
        pixels.data[x*4+3]=Math.round(255*alpha);
      }
      context.putImageData(pixels,0,0);
      this.texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,this.texture);gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,true);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,ramp);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      this.move=event=>{this.input=[event.clientX,event.clientY];this.lastMove=performance.now();request(this);};
      this.leave=()=>{this.input=null;this.previous=null;request(this);};
      this.loss=event=>{event.preventDefault();failed.add(this.element);this.dispose();};
      element.addEventListener('pointermove',this.move,{passive:true});element.addEventListener('pointerleave',this.leave,{passive:true});
      element.addEventListener('pointercancel',this.leave,{passive:true});element.addEventListener('lostpointercapture',this.leave,{passive:true});this.canvas.addEventListener('webglcontextlost',this.loss);
      this.resize=new ResizeObserver(()=>{this.last=0;this.previous=null;request(this);});this.resize.observe(element);
      this.intersection=new IntersectionObserver(entries=>{this.visible=entries[0].isIntersecting;if(!this.visible)this.rest();});this.intersection.observe(element);
      if(getComputedStyle(element).position==='static')element.classList.add('sf-flow-host');
      element.prepend(this.canvas);
      }catch(error){this.dispose();throw error;}
    }
    measure(){const rect=this.element.getBoundingClientRect();return {rect,w:this.element.clientWidth,h:this.element.clientHeight};}
    draw(now,geometry) {
      if (!allowed() || !this.visible || !this.element.isConnected) {this.rest();return false;}
      const start=performance.now(),{rect,w,h}=geometry;
      if(w<1||h<1||rect.width<1||rect.height<1){this.rest();return false;}
      const dt=Math.min(.05,Math.max(.001,(now-(this.last||now-16))/1000));this.last=now;
      const c=this.config;
      let desired=[0,0];
      if(this.input){
        const point=[(this.input[0]-rect.left)*w/rect.width,(this.input[1]-rect.top)*h/rect.height];
        if(this.previous && now-this.lastMove<80){const dx=point[0]-this.previous[0],dy=point[1]-this.previous[1];
          const distance=Math.hypot(dx,dy),maximum=c.radius*c.strength*.45;
          const factor=distance>0?Math.min(maximum/distance,.12/dt):0;desired=[dx*factor,dy*factor];}
        this.pointer=this.pointer?this.pointer.map((p,i)=>p+(point[i]-p)*(1-Math.exp(-c.response*dt))):point;this.previous=point;
      }
      const response=Math.hypot(...desired)>0?c.response:1/c.returnSeconds;
      const blend=1-Math.exp(-response*dt);
      this.pull=this.pull.map((p,i)=>p+(desired[i]-p)*blend);
      if(Math.hypot(...this.pull)<.03 && now-this.lastMove>100){this.rest(false);return false;}
      const ratio=Math.min(1.25,devicePixelRatio||1,1024/w,768/h,Math.sqrt(786432/(w*h)));
      const width=Math.max(1,Math.round(w*ratio)),height=Math.max(1,Math.round(h*ratio));
      if(this.canvas.width!==width||this.canvas.height!==height){this.canvas.width=width;this.canvas.height=height;}
      const gl=this.gl;gl.useProgram(this.program);gl.viewport(0,0,width,height);
      gl.uniform2f(this.uniform.size,w,h);gl.uniform2fv(this.uniform.pointer,this.pointer||[w/2,h/2]);gl.uniform2fv(this.uniform.pull,this.pull);
      gl.uniform1f(this.uniform.radius,c.radius);const angle=c.angle*Math.PI/180;
      gl.uniform2f(this.uniform.direction,Math.cos(angle),Math.sin(angle));gl.uniform1i(this.uniform.ramp,0);
      gl.drawArrays(gl.TRIANGLES,0,6);
      this.canvas.hidden=false;this.element.classList.add('sf-flow-ready');
      const elapsed=performance.now()-start;stats.frames++;stats.drawMilliseconds+=elapsed;
      stats.maximumDrawMilliseconds=Math.max(stats.maximumDrawMilliseconds,elapsed);return true;
    }
    rest(clearInput=true){active.delete(this);this.canvas.hidden=true;this.element.classList.remove('sf-flow-ready');this.pull=[0,0];this.last=0;if(clearInput){this.previous=null;this.pointer=null;this.input=null;}}
    dispose(){if(this.retired)return;this.retired=true;this.rest();this.resize?.disconnect();this.intersection?.disconnect();
      for(const event of ['pointerleave','pointercancel','lostpointercapture'])this.element.removeEventListener(event,this.leave);
      this.element.removeEventListener('pointermove',this.move);this.canvas.removeEventListener('webglcontextlost',this.loss);
      if(this.gl){this.shaders.forEach(s=>this.gl.deleteShader(s));if(this.program)this.gl.deleteProgram(this.program);if(this.texture)this.gl.deleteTexture(this.texture);if(this.buffer)this.gl.deleteBuffer(this.buffer);}
      this.canvas.remove();this.element.classList.remove('sf-flow-host');instances.delete(this.element);}
  }
  function valid(config){return !!config && !(config.version!==1||![config.radius,config.strength,config.response,config.returnSeconds,config.angle].every(Number.isFinite)
    ||config.radius<24||config.radius>1200||config.strength<0||config.strength>1||config.response<.5||config.response>30
    ||config.returnSeconds<.1||config.returnSeconds>5||!Array.isArray(config.stops)||config.stops.length<2||config.stops.length>64
    ||!config.stops.every(s=>s&&[s.position,s.red,s.green,s.blue,s.alpha].every(v=>Number.isFinite(v)&&v>=0&&v<=1)));}
  function update(element,config){
    if(!(element instanceof Element)||!valid(config))return false;
    const item=instances.get(element);
    if(item && item.config.angle===config.angle && JSON.stringify(item.config.stops)===JSON.stringify(config.stops)){
      item.config=config;request(item);
    }else{item?.dispose();failed.delete(element);}
    element.setAttribute('data-siteforge-flow',JSON.stringify(config));scan();return true;
  }

  const scan=()=>{if(!allowed())return;document.querySelectorAll('[data-siteforge-flow]').forEach(element=>{
    if(instances.has(element)||failed.has(element))return;
    try {const config=JSON.parse(element.getAttribute('data-siteforge-flow'));
      if(!valid(config))return;
      if(instances.size>=4)return; // Compiler enforces the same per-page budget.
      instances.set(element,new Flow(element,config));
    }catch{failed.add(element); /* The static authored gradient remains intact. */ }
  });};
  const changed=()=>{if(!allowed()){if(frame)cancelAnimationFrame(frame);frame=0;for(const item of instances.values())item.rest();}else scan();};
  motion.addEventListener('change',changed);hover.addEventListener('change',changed);document.addEventListener('visibilitychange',changed);
  const observer=new MutationObserver(()=>{for(const item of instances.values())if(!item.element.isConnected)item.dispose();scan();});
  observer.observe(document.documentElement,{childList:true,subtree:true});
  const dispose=()=>{disposed=true;if(frame)cancelAnimationFrame(frame);frame=0;observer.disconnect();for(const item of Array.from(instances.values()))item.dispose();
    motion.removeEventListener('change',changed);hover.removeEventListener('change',changed);document.removeEventListener('visibilitychange',changed);};
  addEventListener('pagehide',event=>{if(event.persisted){suspended=true;changed();}else dispose();});
  addEventListener('pageshow',event=>{if(event.persisted&&!disposed){suspended=false;changed();}});
  Object.defineProperty(window,'SiteForgeDecorativeEffects',{value:Object.freeze({version:1,dispose,update,
    statistics:()=>Object.freeze({...stats,instances:instances.size,active:active.size,pendingFrames:frame?1:0})})});
  scan();
})();

"""#
    static let css = #"""
.sf-flow-host { position:relative; }
.sf-flow-canvas { position:absolute;inset:0;width:100%;height:100%;pointer-events:none;border-radius:inherit;z-index:-1; }
.sf-flow-canvas[hidden] { display:none; }
.sf-flow-ready { background-image:none!important;background-color:transparent!important; }
.sf-flow-ready { isolation:isolate; }

"""#
}

/// Numeric-only JSON is escaped as an HTML attribute by SafeHTMLEmitter.
/// It cannot introduce author-provided executable source.
struct FlowOutputConfiguration: Codable, Equatable, Sendable {
    struct Stop: Codable, Equatable, Sendable {
        let position: Double, red: Double, green: Double, blue: Double, alpha: Double
    }
    let version: Int
    let radius: Double, strength: Double, response: Double, returnSeconds: Double, angle: Double
    let stops: [Stop]
    init(flow: CanonicalFlowGradient, layer: CanonicalFillLayer) {
        version = 1; radius = flow.radius; strength = flow.strength; response = flow.response
        returnSeconds = flow.returnSeconds; angle = layer.normalizedAngleDegrees ?? 0
        stops = layer.stops.map { .init(position: $0.position, red: $0.color.red, green: $0.color.green, blue: $0.color.blue, alpha: $0.color.alpha) }
    }
    var json: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? ""
    }
}

enum DecorativeEffectOutput {
    private static func number(_ value: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    static func configuration(_ node: DocumentNode) throws -> FlowOutputConfiguration? {
        guard let flow = try CanonicalFlowGradient.resolve(node), flow.enabled else { return nil }
        guard let layer = CanonicalFlowGradient.gradient(on: node) else { throw DesignInspectorError.unavailable(CanonicalFlowGradient.unavailableReason) }
        return .init(flow: flow, layer: layer)
    }
    static func configurations(_ page: DocumentPage) throws -> [NodeID: FlowOutputConfiguration] {
        var result: [NodeID: FlowOutputConfiguration] = [:]
        for node in page.nodes { if let value = try configuration(node) { result[node.id] = value } }
        guard result.count <= 4 else { throw DesignInspectorError.unavailable("Use at most four enabled flowing gradients per page.") }
        return result
    }
    static func glassCSS(_ nodes: [DocumentNode]) throws -> String {
        try nodes.compactMap { node -> String? in
            guard let glass = try CanonicalGlassSurface.resolve(node) else { return nil }
            let selector = ".sf-node-" + node.id.description
            let color = glass.fallback
            let fallback = "rgb(\(number(color.red * 255)) \(number(color.green * 255)) \(number(color.blue * 255)))"
            let dark = glass.darkFallback ?? color
            let darkFallback = "rgb(\(number(dark.red * 255)) \(number(dark.green * 255)) \(number(dark.blue * 255)))"
            let blur = number(glass.blur)
            return """
            @supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) { \(selector) { background:\(fallback)!important; } }
            @supports ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) {
              @media (prefers-reduced-transparency:no-preference) {
                \(selector) { backdrop-filter:blur(\(blur)px);-webkit-backdrop-filter:blur(\(blur)px); }
              }
            }
            @media (prefers-reduced-transparency:reduce) { \(selector) { background:\(fallback)!important;backdrop-filter:none;-webkit-backdrop-filter:none; } }
            @media (prefers-color-scheme:dark) {
              @supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) { \(selector) { background:\(darkFallback)!important; } }
              @media (prefers-reduced-transparency:reduce) { \(selector) { background:\(darkFallback)!important; } }
            }
            """
        }.joined(separator: "\n")
    }
}
