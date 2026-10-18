`installer-v2.tar.gz` is the immutable v2.0 source subset used by the upgrade
regression. It contains the actual installer, lifecycle modules, runtime and
shell integration, rather than a reimplementation of the old manifest format.
Tests unpack and run it only in their disposable HOME, with controlled tools.

Source: `68686cf` in https://github.com/seanap/fzd.
SHA256: `99a74bc46ace528b4ce89b03a88726b9f0ceb498518668ddbc0dec1ae819b1cd`.

Reproduce from the repository (no tag changes or downloads):

```bash
git archive 68686cf install.sh installer shell lib fzd.sh fzd.conf.example LICENSE.txt \
  | gzip -n -9 > tests/fixtures/installer-v2.tar.gz
```
