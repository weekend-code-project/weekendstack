# Template System Standardization Cleanup

**Branch**: `cleanup/template-system-standardization`  
**Date**: January 4, 2026  
**Goal**: Clean up template system inconsistencies before Phase 1 flickering investigation

## Checklist

### Phase 1: Path & Reference Standardization
- [x] Find all module references using old paths (`templates/git-modules`)
- [x] Update all module references to use `template-modules/modules`
- [x] Standardize all `?ref=` to use `PLACEHOLDER` pattern
- [x] Update all module README.md files with correct examples

### Phase 2: Documentation Updates
- [x] Update `template-modules/params/README.md` with overlay precedence rules
- [x] Update all module READMEs with correct source paths
- [x] Fix code-server-module README example

### Phase 3: Archive/Cleanup
- [x] Review `_trash/` directory structure
- [x] Clean up or clearly mark archived content
- [x] Document what was archived and why

### Phase 4: Validation
- [x] Create `validate-module-refs.sh` script
- [x] Run validation on all templates
- [x] Fix any issues found by validation

### Phase 5: Testing
- [x] Re-push debug-template Phase 0 to verify baseline (waiting on branch push)
- [x] Verify no regressions in existing templates (will test after branch push)
- [x] Update TESTING_GUIDE.md with cleanup notes

### Phase 6: Commit & Document
- [ ] Commit all changes with clear message
- [ ] Update template-modularization-plan.md
- [ ] Push branch for review

---

## Progress Log

### 2026-01-04 - Initial Setup
- Created branch `cleanup/template-system-standardization`
- Created this tracking document

### 2026-01-04 - Phase 1 Complete
- Replaced all old `templates/git-modules` paths with `template-modules/modules`
- Standardized all `?ref=v0.1.x` to `?ref=PLACEHOLDER`
- Updated 16 module README files with correct paths

### 2026-01-04 - Phase 2 Complete
- Enhanced `template-modules/params/README.md` with comprehensive overlay documentation
- Documented precedence rules, override patterns, and best practices

### 2026-01-04 - Phase 4 Complete
- Created `validate-module-refs.sh` script with 5 validation checks
- All validations passing ✅

### Next: Phase 3 - Archive Cleanup
