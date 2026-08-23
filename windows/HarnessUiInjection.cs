namespace DeepSeekHarnessGlass.Windows;

/// <summary>
/// Cross-platform Glass-only adjustments for the official Harness web UI.
/// They intentionally identify stable DOM semantics instead of upstream CSS
/// Module class names, so official source and plugin contracts remain intact.
/// </summary>
internal static class HarnessUiInjection
{
    internal const string Script = """
        (function () {
          function install() {
            if (!document.documentElement) return;
            if (!document.getElementById('dsh-glass-shell-style')) {
              var style = document.createElement('style');
              style.id = 'dsh-glass-shell-style';
              style.textContent = `
                [data-dsh-glass-brand="name"] + span {
                  display: inline-flex !important;
                  flex: none !important;
                  flex-shrink: 0 !important;
                  align-items: center !important;
                  justify-content: center !important;
                  align-self: center !important;
                  box-sizing: border-box !important;
                  height: 16px !important;
                  min-width: max-content !important;
                  white-space: nowrap !important;
                  line-height: 16px !important;
                  vertical-align: middle !important;
                  transform: translateY(-1px) !important;
                }
                [data-dsh-glass-brand="name"] + span > [data-dsh-glass-revision-label="text"] {
                  display: block !important;
                  line-height: 1 !important;
                  transform: translateY(1px) !important;
                }
                [data-dsh-glass-brand-name-row] {
                  gap: 3px !important;
                }
                [data-dsh-glass-brand-row] {
                  gap: 3px !important;
                }
                [data-dsh-glass-brand-identity] {
                  gap: 5px !important;
                }
                [data-dsh-glass-brand="name"] {
                  font-size: 16px !important;
                }
              `;
              (document.head || document.documentElement).appendChild(style);
            }

            if (!document.body) {
              document.addEventListener('DOMContentLoaded', install, { once: true });
              return;
            }

            function applySidebarBrand() {
              var spans = document.querySelectorAll('span');
              for (var i = 0; i < spans.length; i++) {
                var span = spans[i];
                if (span.children.length === 0 &&
                    span.textContent.trim() === 'DSH Local Build') {
                  span.textContent = 'DeepSeek Harness';
                  span.setAttribute('data-dsh-glass-brand', 'name');
                }
                if (span.getAttribute('data-dsh-glass-brand') !== 'name') continue;
                if (span.parentElement) {
                  span.parentElement.setAttribute('data-dsh-glass-brand-name-row', '');
                  if (span.parentElement.parentElement) {
                    span.parentElement.parentElement.setAttribute(
                      'data-dsh-glass-brand-identity', ''
                    );
                  }
                }
                var brandButton = span.closest('button');
                if (brandButton && brandButton.parentElement) {
                  brandButton.parentElement.setAttribute('data-dsh-glass-brand-row', '');
                }
                var revision = span.nextElementSibling;
                if (!revision || revision.tagName !== 'SPAN') continue;
                if (revision.children.length !== 0) continue;
                var commit = revision.textContent.trim();
                if (!/^[0-9a-f]{7,40}$/i.test(commit)) continue;
                var label = document.createElement('span');
                label.setAttribute('data-dsh-glass-revision-label', 'text');
                label.textContent = commit.slice(0, 7);
                revision.textContent = '';
                revision.appendChild(label);
              }
            }

            function applyDefaultSidebarWidth() {
              var overlay = document.querySelector('[data-shell-overlay]');
              var frame = overlay && overlay.parentElement;
              if (!frame) return;
              var grid = frame.style.getPropertyValue('grid-template-columns');
              var tracks = grid.match(/-?\d+(?:\.\d+)?px/g);
              if (!tracks || tracks.length < 2) return;

              var sidebar = parseFloat(tracks[0]);
              var details = parseFloat(tracks[tracks.length - 1]);
              if (!frame.hasAttribute('data-dsh-glass-sidebar-offset')) {
                if (Math.round(sidebar) !== 280) return;
                frame.setAttribute('data-dsh-glass-sidebar-offset', '15');
              }
              if (frame.style.getPropertyPriority('grid-template-columns') === 'important') return;
              if (sidebar <= 56) return;

              var widened = sidebar + 15;
              frame.style.setProperty(
                'grid-template-columns',
                widened + 'px minmax(0, 1fr) ' + details + 'px',
                'important'
              );
              var sidebarHandle = frame.querySelector('[data-side="sidebar"]');
              if (!sidebarHandle) return;
              if (Math.round(parseFloat(sidebarHandle.style.left || '0')) !== Math.round(sidebar)) return;
              sidebarHandle.style.setProperty('left', widened + 'px', 'important');
            }

            var sidebarWidthPending = false;
            function scheduleDefaultSidebarWidth() {
              if (sidebarWidthPending) return;
              sidebarWidthPending = true;
              requestAnimationFrame(function () {
                sidebarWidthPending = false;
                applyDefaultSidebarWidth();
              });
            }

            applySidebarBrand();
            scheduleDefaultSidebarWidth();

            var contentObserver = new MutationObserver(function () {
              applySidebarBrand();
              scheduleDefaultSidebarWidth();
            });
            contentObserver.observe(document.body, { childList: true, subtree: true });

            var sidebarWidthObserver = new MutationObserver(scheduleDefaultSidebarWidth);
            sidebarWidthObserver.observe(document.body, {
              attributes: true,
              attributeFilter: ['style'],
              subtree: true
            });
          }

          install();
        })();
        """;
}
