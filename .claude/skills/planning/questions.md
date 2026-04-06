# Interactive Planning Questions

These questions should be asked during a planning session to understand the feature and design the solution.

## Feature Scope Questions

**Q: Where should this feature be implemented?**
- [ ] App only (Bar Ticket macOS app)
- [ ] Website only (bar-ticket-site)
- [ ] Both app and website
- [ ] Other: ___________________

**Q: Is this a user-facing feature or internal improvement?**
- [ ] User-facing (affects end-user experience)
- [ ] Internal improvement (refactoring, performance, etc.)
- [ ] Both
- [ ] Other: ___________________

## Technical Design Questions

**Q: What's the main problem or goal?**
(Free text response)

**Q: Which part of the app does this affect?**
- [ ] File watching / TODO detection
- [ ] GitHub API integration
- [ ] Notch UI / notifications
- [ ] Settings / configuration
- [ ] Menu bar app functionality
- [ ] Multiple areas
- [ ] Other: ___________________

**Q: Does this require new dependencies?**
- [ ] No, use existing dependencies
- [ ] Maybe, depends on implementation
- [ ] Yes, need to add package(s): ___________________

**Q: What's the implementation complexity?**
- [ ] Simple (single file, < 50 lines)
- [ ] Moderate (few files, architectural consideration)
- [ ] Complex (multiple components, significant refactor)
- [ ] Uncertain, need to research

## Performance & Integration Questions

**Q: Are there performance concerns?**
- [ ] No, performance shouldn't be impacted
- [ ] Might affect file watching latency
- [ ] Might affect notch animation smoothness
- [ ] Need to optimize for performance
- [ ] Other: ___________________

**Q: Does this integrate with existing systems?**
- [ ] Self-contained feature
- [ ] Integrates with state management (AppState)
- [ ] Integrates with file watching
- [ ] Integrates with GitHub API
- [ ] Multiple integration points
- [ ] Other: ___________________

## User Interaction Questions

**Q: How will users interact with this feature?**
- [ ] Automatic (no user action needed)
- [ ] Menu bar settings/toggle
- [ ] Notch interaction
- [ ] File-based configuration
- [ ] Other: ___________________

**Q: Should this be configurable?**
- [ ] No configuration needed
- [ ] Settings in menu bar app
- [ ] Settings on website
- [ ] Both app and website settings
- [ ] Other: ___________________

## Timeline & Priority Questions

**Q: What's the priority level?**
- [ ] Critical (high-impact bug fix)
- [ ] High (requested feature, clear value)
- [ ] Medium (nice to have)
- [ ] Low (future consideration)

**Q: Are there any constraints or blockers?**
(Free text response)

---

## Using these questions

1. Ask questions in logical groups (scope → design → integration)
2. Ask yes/no or single-select questions first for quick decisions
3. Use multi-select when multiple options apply
4. **Always include "Other: ___" option** for custom answers
5. Follow up on responses with "Why?" or "Tell me more about..."
6. Use answers to inform architecture and implementation steps
7. Update the plan file as answers come in, progressively refining sections
