# Claude Code Brave MCP 快速部署包

这个目录已经包含：

- `brave api.txt`
  内含 Brave Search API 地址和两个 API key。
- `.mcp.json`
  Claude Code 项目级 MCP 配置。
- `tools/brave_mcp_server.py`
  Brave Search 的 MCP 包装器。
- `tools/start_brave_mcp.cmd`
  Claude Code 启动 MCP 服务时调用的入口。
- `setup_brave_mcp.ps1`
  一键创建 `.venv` 并安装依赖。
- `claude_prompt.txt`
  可以直接贴给 Claude Code 的部署 prompt。

## 在另一台电脑上的使用步骤

1. 解压整个压缩包。
2. 进入解压后的目录。
3. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_brave_mcp.ps1
```

4. 在该目录启动 Claude Code。
5. 验证 MCP 是否连通：

```powershell
claude mcp get brave-search
```

6. 在 Claude Code 中测试：

```text
用 brave-search 搜索 PUMA560，并给我前3条结果和链接。
```

## 说明

- 这个部署包默认直接读取同目录下的 `brave api.txt`，不需要手动设置环境变量。
- 如果第一把 key 失效，服务会自动尝试文件中的下一把 key。
- 该包面向 Windows + Claude Code。
