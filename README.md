# Scoop Bucket

This is a [Scoop](https://scoop.sh) bucket based on [Scoop BucketTemplate](https://github.com/ScoopInstaller/BucketTemplate) containing [manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests) for Windows applications.

## Applications

This bucket currently contains the following applications:

| Application | Description |
| ----------- | ----------- |
| [dblab](https://github.com/danvergara/dblab) | The database client every command line junkie deserves. |
| [envx](https://github.com/mikeleppane/envx) | A powerful and secure environment variable manager for developers, featuring an intuitive Terminal User Interface (TUI) and comprehensive command-line interface. |
| [filebrowser](https://filebrowser.org) | 📂 Web File Browser |
| [flow](https://flow-control.dev) | Flow Control: a programmer's text editor |
| [gonzo](https://www.controltheory.com/gonzo/) | Gonzo! The Go based TUI log analysis tool |
| [halp](https://halp.cli.rs/) | A CLI tool to get help with CLI tools 🐙 |
| [hl](https://github.com/pamburus/hl) | A fast and powerful log viewer and processor that converts JSON logs or logfmt logs into a clear human-readable format. |
| [lazyssh](https://github.com/Adembc/lazyssh) | A terminal-based SSH manager inspired by lazydocker and k9s - Written in go |
| [projecteye](https://github.com/Planshit/ProjectEye) | 护眼 - 定时提醒 |
| [snibypassgui](https://github.com/racpast/SNIBypassGUI) | 直连 GitHub、Discord、GreasyFork等 \| 一个通过 Nginx 反向代理实现绕过 SNI 阻断的工具 |
| [sshx](https://sshx.io) | Fast, collaborative live terminal sharing over the web |
| [sunnycapturer](http://sunnycapturer.xmuli.tech/) | 简单且漂亮的跨平台截图软件，支持离线 OCR、图片翻译、贴图和钉图等功能 |
| [tiny-rdm](https://github.com/tiny-craft/tiny-rdm) | 一个现代化轻量级的跨平台Redis桌面客户端 |


## Usage

To add this bucket to your Scoop installation:

```powershell
scoop bucket add ylem-bucket https://github.com/Ylemir/Scoop-Bucket
```

To install any of the applications:

```powershell
scoop install <app-name>

# or

scoop install ylem-bucket/<app-name>
```

## Contributing

If you'd like to contribute to this bucket, feel free to submit a pull request with a new manifest file or improvements to existing ones.

You can use the script in [scripts/gen-manifest.py](scripts/gen-manifest.py) to help generate manifest files for GitHub releases:

```shell
uv run --with httpx .\scripts\gen-manifest.py <github-url>
```

Alternatively, you can manually create a manifest. See the [Scoop Wiki](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests) for more details.

## License

The manifests and scripts in this repository are licensed under the MIT License unless otherwise specified.
