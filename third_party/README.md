# Third-party distribution notices

Marknote uses installed third-party software in a locally bundled ArkWeb renderer.
The commercial closed-source distribution permission is provided by each upstream license;
Marknote does not claim ownership of their code, fonts, or trademarks.

Build the renderer with `npm install && npm run build` in `renderer/`.
That command reads the actual installed production dependency graph, collects every
LICENSE and NOTICE it finds, and writes `entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt`.
The app exposes that full text under **更多 → 开源许可证与隐私说明**.
Unknown license types or missing license files stop the build. KaTeX fonts are
separately licensed: `OFL.txt` is required and appended in full; the build
fails if it is missing or is not the SIL Open Font License.

## Selected libraries

| Library | Pinned version | License | Upstream |
| --- | --- | --- | --- |
| markdown-it | 15.0.3 | MIT | https://github.com/markdown-it/markdown-it |
| @mdit/plugin-katex | 1.1.4 | MIT | https://github.com/mdit-plugins/mdit-plugins |
| KaTeX code | 0.19.1 | MIT | https://github.com/KaTeX/KaTeX |
| KaTeX math fonts (bundled with KaTeX) | 0.19.1 | **SIL OFL-1.1** | `katex/dist/fonts/OFL.txt` within the installed npm package |
| DOMPurify | 3.4.17 | Apache-2.0 OR MPL-2.0; **Apache-2.0 chosen** | https://github.com/cure53/DOMPurify |

Build-time tooling (Vite, TypeScript, vite-plugin-singlefile) is not shipped in the HAP.
Runtime transitive dependencies are determined from the installed package graph; their
license text is also included in the generated in-app notice. Do not manually replace
that output with this summary when publishing.

The app icon is newly generated in this repository without third-party artwork.
Store listing graphics, translated copy, imported documents and future theme/font
resources need rights review separately if they are shipped with the app.
