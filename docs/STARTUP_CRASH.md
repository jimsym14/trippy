# Device startup crash

Reproduced on the connected iPhone running iOS 27.2 on November 3, 2026. LLDB stopped at `TripFlowView.body` with `EXC_BAD_ACCESS (code=2)` while Swift resolved the root view's generic type. The top frame was `swift::SubstGenericParametersFromMetadata::getMetadata`, followed by repeated mangled-type and generic-argument decoding frames. The crash occurred before the map appeared.

The root navigation composed the map, Library, brief and presentation content as one deeply nested concrete SwiftUI type. `TrippyScreen` now gives each screen a non-generic view boundary with a deferred content closure and type erasure at that boundary. Library header/collection and modal screen content use the same boundary. Collection rows retain their existing concrete types, IDs, bindings and lazy stacks.

Xcode's shared launch scheme now attaches LLDB so device failures remain inspectable. Device-only debug-dylib signing settings and `COPY_PHASE_STRIP = NO` are preserved.

Verification:

- The signed device build succeeded with no code-signing or signed-binary stripping errors.
- The rebuilt app stayed running on the connected phone after passing the previous crash point. A final normal launch was rechecked after a further 30-second observation interval, with no startup exception.
- Simulator compilation passed with no warnings or errors.
- Trip draft, map clustering/search-layout and Library grouping/contrast regression checks passed.

An optional Xcode view-hierarchy capture attempt ended the debug session with signal 9. The final successful verification used a normal launch without that capture; a rendered device-view capture was not completed.
