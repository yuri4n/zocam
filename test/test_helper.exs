# [claude-code] All zocam modules are fully implemented, so there is
# no :not_implemented backlog here (unlike the parent app). The
# exclusion stays so a future backlog test behaves the same way in
# both projects.
ExUnit.start(exclude: [:skip, :not_implemented])
