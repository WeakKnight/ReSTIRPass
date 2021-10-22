from falcor import *

def render_graph_DefaultRenderGraph():
    g = RenderGraph('DefaultRenderGraph')
    loadRenderPassLibrary('BSDFViewer.dll')
    loadRenderPassLibrary('AccumulatePass.dll')
    loadRenderPassLibrary('Antialiasing.dll')
    loadRenderPassLibrary('DepthPass.dll')
    loadRenderPassLibrary('DebugPasses.dll')
    loadRenderPassLibrary('BlitPass.dll')
    loadRenderPassLibrary('CSM.dll')
    loadRenderPassLibrary('GBuffer.dll')
    loadRenderPassLibrary('ErrorMeasurePass.dll')
    loadRenderPassLibrary('FLIPPass.dll')
    loadRenderPassLibrary('TemporalDelayPass.dll')
    loadRenderPassLibrary('ForwardLightingPass.dll')
    loadRenderPassLibrary('ImageLoader.dll')
    loadRenderPassLibrary('MegakernelPathTracer.dll')
    loadRenderPassLibrary('SVGFPass.dll')
    loadRenderPassLibrary('MinimalPathTracer.dll')
    loadRenderPassLibrary('OptixDenoiser.dll')
    loadRenderPassLibrary('PassLibraryTemplate.dll')
    loadRenderPassLibrary('PixelInspectorPass.dll')
    loadRenderPassLibrary('ReSTIRPass.dll')
    loadRenderPassLibrary('SceneDebugger.dll')
    loadRenderPassLibrary('SimplePostFX.dll')
    loadRenderPassLibrary('SkyBox.dll')
    loadRenderPassLibrary('SSAO.dll')
    loadRenderPassLibrary('TestPasses.dll')
    loadRenderPassLibrary('ToneMapper.dll')
    loadRenderPassLibrary('Utils.dll')
    loadRenderPassLibrary('WhittedRayTracer.dll')
    ReSTIRPass = createPass('ReSTIRPass')
    g.addPass(ReSTIRPass, 'ReSTIRPass')
    SimplePostFX = createPass('SimplePostFX', {'enabled': True, 'wipe': 0.0, 'bloomAmount': 0.0, 'starAmount': 0.0, 'starAngle': 0.10000000149011612, 'vignetteAmount': 0.0, 'chromaticAberrationAmount': 0.0, 'barrelDistortAmount': 0.0, 'saturationCurve': float3(1.000000,1.000000,1.000000), 'colorOffset': float3(0.500000,0.500000,0.500000), 'colorScale': float3(0.500000,0.500000,0.500000), 'colorPower': float3(0.500000,0.500000,0.500000), 'colorOffsetScalar': 0.0, 'colorScaleScalar': 0.0, 'colorPowerScalar': 0.0})
    g.addPass(SimplePostFX, 'SimplePostFX')
    ToneMapper = createPass('ToneMapper', {'useSceneMetadata': True, 'exposureCompensation': 0.0, 'autoExposure': False, 'filmSpeed': 100.0, 'whiteBalance': False, 'whitePoint': 6500.0, 'operator': ToneMapOp.Aces, 'clamp': True, 'whiteMaxLuminance': 1.0, 'whiteScale': 11.199999809265137, 'fNumber': 1.0, 'shutter': 1.0, 'exposureMode': ExposureMode.AperturePriority})
    g.addPass(ToneMapper, 'ToneMapper')
    AccumulatePass = createPass('AccumulatePass', {'enabled': True, 'autoReset': True, 'precisionMode': AccumulatePrecision.Single, 'subFrameCount': 0, 'maxAccumulatedFrames': 0})
    g.addPass(AccumulatePass, 'AccumulatePass')
    g.addEdge('SimplePostFX.dst', 'ToneMapper.src')
    g.addEdge('ReSTIRPass.output', 'AccumulatePass.input')
    g.addEdge('AccumulatePass.output', 'SimplePostFX.src')
    g.markOutput('ToneMapper.dst')
    return g

DefaultRenderGraph = render_graph_DefaultRenderGraph()
try: m.addGraph(DefaultRenderGraph)
except NameError: None
