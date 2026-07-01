package dev.metalcraft.engine.mixin;

import org.spongepowered.asm.mixin.Mixin;

import net.minecraft.client.render.chunk.ChunkBuilder;

/**
 * Terrain mesh interception point for the experimental Metal backend.
 *
 * <p>Design (see docs/METALCRAFT_ENGINE.md, Stage 3): after the chunk builder
 * finishes meshing a section, the vertex data is offered to
 * {@code MetalCraftMod.backend().offerChunkMesh(...)} as a direct ByteBuffer.
 * If the backend takes ownership (Metal terrain takeover), the vanilla GL
 * upload/draw for that section is skipped; otherwise vanilla proceeds
 * untouched.
 *
 * <p>The exact injection targets are version-specific (mappings move between
 * Minecraft releases), so the concrete @Inject handlers live in
 * version-adapter subpackages as they are implemented per supported version.
 * Keeping the mixin class registered documents the seam and reserves the
 * injection point in the pipeline.
 */
@Mixin(ChunkBuilder.class)
public abstract class MixinChunkUpload {
}
