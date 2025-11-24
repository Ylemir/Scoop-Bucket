import hashlib
import json
import logging
import os
import re
import sys
import tempfile
import zipfile
from urllib.parse import urlparse

import httpx

# 设置日志配置
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(filename)s - %(funcName)s (%(lineno)s line): %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.DEBUG,
)
logger = logging.getLogger(__name__)

GITHUB_API = "https://api.github.com"


def get_owner_repo(url_or_name: str):
    """解析 GitHub 仓库 URL 或 owner/repo"""
    if "github.com" in url_or_name:
        parts = urlparse(url_or_name).path.strip("/").split("/")
        if len(parts) >= 2:
            return f"{parts[0]}/{parts[1]}"
    elif "/" in url_or_name:
        return url_or_name
    raise ValueError("无法解析 GitHub 仓库地址，请输入 'owner/repo' 或完整 URL")


def sha256sum(filename):
    """计算 SHA256 校验值"""
    h = hashlib.sha256()
    with open(filename, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_bin_from_zip(zip_path):
    """尝试从 zip 中找出顶层 exe"""
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            for name in zf.namelist():
                if re.match(r"^[^/\\]+\.exe$", name, re.I):
                    return os.path.basename(name)
    except zipfile.BadZipFile:
        pass
    return None


def guess_best_asset(assets):
    """挑选最可能的 Windows 资产"""
    if not assets:
        return None

    # 更精细的资产排序规则
    def asset_rank_key(asset):
        name = asset["name"].lower()

        # 首先排除明显不需要的文件类型
        if re.search(r"\.src|source|sources|src|darwin|linux|macos|android|ios", name):
            return (10, 0, 0, 0, 0)

        # 优先选择Windows相关文件
        win_score = 0 if re.search(r"win|windows", name) else 1

        # 架构评分 (优先级: x64/amd64 > x86 > 通用)
        arch_score = 5
        if re.search(r"x64|x86_64|x86-64|amd64|64bit", name):
            arch_score = 0
        elif re.search(r"x86|win32|ia32|32bit", name):
            arch_score = 1
        elif re.search(r"arm64", name):
            arch_score = 9

        # 文件类型评分 (优先级:.zip | .7z > .exe > .tar.gz > 其他)
        type_score = 10
        if name.endswith((".zip", ".7z")):
            type_score = 0
        elif name.endswith(".exe"):
            type_score = 2
        elif name.endswith(".tar.gz"):
            type_score = 5

        # 优先编写版本
        port_score = 1 if re.search(r"portable|port", name) else 0

        return (win_score, arch_score, type_score, port_score, name)

    ranked = sorted(assets, key=asset_rank_key)
    return ranked[0]


def get_repo(client, owner_repo):
    """获取仓库信息 (https://docs.github.com/zh/rest/repos/repos?apiVersion=2022-11-28#get-a-repository)"""
    url = f"{GITHUB_API}/repos/{owner_repo}"
    r = client.get(url)
    if r.status_code == 200:
        return r.json()
    else:
        raise RuntimeError(f"⚠️ 无法获取仓库信息 ({r.status_code}): {r.text}")


def get_license(client, owner_repo):
    """获取 LICENSE 类型"""
    url = f"{GITHUB_API}/repos/{owner_repo}/license"
    r = client.get(url)
    if r.status_code == 200:
        data = r.json()
        lic = data.get("license", {})
        return lic.get("spdx_id", "unknown")
    elif r.status_code == 404:
        return "unknown"
    else:
        logger.warning(f"⚠️ 无法获取 license ({r.status_code}): {r.text}")
        return "unknown"


def get_release(client, owner_repo, version=None):
    """获取 release 数据"""
    api_base = f"{GITHUB_API}/repos/{owner_repo}/releases"
    if version:
        url = f"{api_base}/tags/{version}"
    else:
        url = f"{api_base}/latest"

    r = client.get(url)
    if r.status_code != 200:
        raise RuntimeError(f"获取 release 失败: {r.text}")
    return r.json()


def download_asset(client, url, dest):
    """下载资产"""
    with client.stream("GET", url) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    return dest


def generate_manifest(owner_repo, version=None, github_token=None):
    headers = {"User-Agent": "scoop-generator"}
    if github_token:
        headers["Authorization"] = f"token {github_token}"

    with httpx.Client(
        headers=headers,
        follow_redirects=True,
        timeout=60.0,
        verify=False,
    ) as client:
        repo = get_repo(client, owner_repo)
        app_name = repo.get("name")
        logger.debug(f"repo: {json.dumps(repo, ensure_ascii=False, indent=2)}")
        # 获取 release
        release = get_release(client, owner_repo, version)
        logger.debug(f"release: {json.dumps(release, ensure_ascii=False, indent=2)}")
        assets = release.get("assets", [])
        asset = guess_best_asset(assets)
        if not asset:
            raise RuntimeError("❌ 未找到合适的 release 资产")

        asset_url = asset["browser_download_url"]
        asset_name = asset["name"]
        version = (version or release.get("tag_name", "")).lstrip("v")

        logger.info(f"✅ 找到 release 资产: {asset_name}")
        logger.info(f"📦 版本: {version}")
        # logger.info("⬇️  下载中...")

        # tmpdir = tempfile.mkdtemp(prefix="scoop_manifest_")
        # file_path = os.path.join(tmpdir, asset_name)
        # download_asset(client, asset_url, file_path)

        # sha = sha256sum(file_path)
        sha = asset.get("digest")
        logger.info(f"🔒 {sha}")

        bin_name = f"{app_name}.exe"
        if asset_name.endswith(".zip"):
            # bin_name = extract_bin_from_zip(file_path)
            pass
        elif asset_name.endswith(".exe"):
            pass
        bin = bin_name if bin_name == asset_name else [[asset_name, app_name]]

        # license_type = get_license(client, owner_repo)
        license = repo.get("license") or {}
        license_type = license.get("spdx_id", "unknown")
        logger.info(f"📄 LICENSE: {license_type}")

        manifest = {
            "version": version,
            "description": repo.get("description") or release.get("name"),
            "homepage": repo.get("homepage") or f"https://github.com/{owner_repo}",
            "bin": bin,
            "shortcuts": [[bin_name, app_name]],
            "license": license_type,
            "architecture": {"64bit": {"url": asset_url, "hash": sha}},
            "checkver": {"github": f"https://github.com/{owner_repo}"},
            "autoupdate": {
                "architecture": {
                    "64bit": {
                        "url": re.sub(version, "$version", asset_url),
                    }
                }
            },
        }
        output_file = f"bucket/{app_name.lower()}.json"
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)

        logger.info(f"\n✅ 已生成 Scoop manifest: {output_file}")
        # logger.info(f"🗂  临时文件路径: {tmpdir}")
        return output_file


if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error(
            "用法: python gen_manifest.py <owner/repo 或 GitHub URL> [version] [token]"
        )
        sys.exit(1)

    repo = sys.argv[1]
    version = (
        sys.argv[2]
        if len(sys.argv) >= 3 and not sys.argv[2].startswith("ghp_")
        else None
    )
    token = os.environ.get("GITHUB_TOKEN")

    # 支持直接传 GitHub token
    if len(sys.argv) >= 3 and sys.argv[2].startswith("ghp_"):
        token = sys.argv[2]
    elif len(sys.argv) >= 4:
        token = sys.argv[3]

    try:
        repo_name = get_owner_repo(repo)
        generate_manifest(repo_name, version, token)
    except Exception as e:
        logger.error("❌ 出错:", exc_info=True)
        sys.exit(1)
