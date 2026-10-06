Shader harness with SHADER_SEED_AB=true on the Pixel 6a (Vulkan): every case
rendered with the frost seed pass (candidate) and without it (baseline), the
same runtime shaders. Built from the exploration tree, where every frosted
layer was seeded; the landed flag seeds only the lens-frost cases (the
others are then 0 by construction, host Impeller confirms).
