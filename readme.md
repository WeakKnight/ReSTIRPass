# ReSTIR Pass

a falcor render-pass for ReSTIR Direct Lighting

## How to use

Add this project into Falcor solution just like other render-passes.  
![file-tree-layout](images/layout.png)  
After building this pass, you can load the render graph scripts under project folder via Mogwai.  
![render-graph-files](images/rendergraph.jpg)
## Limitation

> I only used Falcor Light Sampler, including a hierarchical envmap sampler(see EnvMapSampler) and a Alias-Method power based emissive triangle sampler(see EmissivePowerSampler). If you want to support more light types(such as point light, directional light) or more efficient light sampling technique, you need to implement corresponding light samplers as initial sampling primitives.

> I used VBuffer instead of GBuffer which may lead to more computation overhead

> I did not do tricks like Pre-Sampling, Decoupled Shading(see [HPG2021 Rearch ReSTIR](https://research.nvidia.com/publication/2021-07_Rearchitecting-Spatiotemporal-Resampling)). If you want to improve performance further, you need implement this kind of things by yourself

> I only implemented spatial resampling debias. You need implement temporal debias by yourself.