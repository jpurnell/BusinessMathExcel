# Idea: Immersive Coherence Environment (Vision Pro)

**Status:** Stub — separate design session after v1 breathing sphere + tint ships
**Depends on:** visionOS app target (PROPOSAL_visionos_target.md Phase 1)

## Concept

A full immersive environment where the user's coherence state manifests as a spatial phenomenon. The entire space responds to biofeedback in real time.

### Coherence-Driven Environment States

- **Low (0-30%):** Dim, slightly foggy space. Particles drift chaotically. Colors muted/desaturated. Space feels restless.
- **Mid (30-60%):** Fog lifts. Particles organize into slow spirals. Warm colors emerge. Space settles.
- **High (60-100%):** Crystal clear. Particles form geometric mandala patterns synchronized to breathing. Rich warm light. Space feels alive and ordered.

### Breathing Integration
- Environment pulses — walls/space gently expand on inhale, contract on exhale
- Particles flow inward on inhale, outward on exhale
- The HRV oscillation rendered as a flowing ribbon/wave in 3D — smooth when coherent, jagged when chaotic

### Visualization Styles
- **Particles** — abstract particle field (default)
- **Ocean** — calm water surface, waves respond to coherence
- **Forest** — abstract canopy, light filters through based on coherence
- **Geometric** — sacred geometry patterns that coalesce with coherence

### Technical Considerations
- RealityKit `ParticleEmitterComponent` for particle systems
- Custom shaders for fog/glow effects
- `.full` immersion mode (requires App Store justification for meditation)
- Performance profiling on hardware essential (particle count, shader complexity)
- Multiple environments = bundled assets (~2-5 MB each)

## Open Questions
- How many styles for v1 of the immersive environment?
- Should environment transition be continuous or discrete (coherence zones)?
- SharePlay: shared meditation environment worth architecting for?
