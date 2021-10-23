# ReSTIR Pass

a falcor render-pass for ReSTIR Direct Lighting

## How to use

Add this project into Falcor solution just like other render-passes.
![file-tree-layout](images/layout.png)
After building this pass, you can load the render graph scripts under project folder via Mogwai.
![file-tree-layout](images/rendergraph.jpg)
## Limitation

> I only used Falcor Light Sampler, a hierarchical envmap sampler(see EnvMapSampler) and a Alias-Method power based emissive triangle sampler(see EmissivePowerSampler). If you want to support more light types(such as point light, directional light) or more efficient light sampling technique, you need to implement corresponding light sampler as a initial sampling primitive.

> I used VBuffer instead of GBuffer which may cause extra computation overhead

> I did not do tricks like Pre-Sampling, De-Coupled Shading. If you want to improve memory efficiency, you need implement this kind of things by yourself

> I only implemented spatial resampling debias. You need implement temporal debias by your self.