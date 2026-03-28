# Makefile for achive - A股、港股、美股实时行情插件

# 配置变量
EMACS ?= emacs
EMACSFLAGS ?= -Q --batch
ERT ?= $(EMACS) $(EMACSFLAGS) -l ert
PACKAGE_NAME = achive
VERSION = 1.0
AUTHOR = zakudriver
EMAIL = zy.hua1122@gmail.com
URL = https://github.com/zakudriver/achive

# 文件列表
EL_FILES = achive.el
TEST_FILE = test-achive.el
README_FILE = README.org
LICENSE_FILE = LICENSE
IMAGES_DIR = imgs

# 安装路径
INSTALL_DIR ?= $(shell $(EMACS) $(EMACSFLAGS) --eval "(princ (expand-file-name \"~/.emacs.d/elpa/$(PACKAGE_NAME)-$(VERSION)\"))")

# 默认目标
.PHONY: all
all: compile test

# 编译目标
.PHONY: compile
compile: $(EL_FILES)
	@echo "编译 achive 文件..."
	@for file in $(EL_FILES); do \
		echo "编译 $$file..."; \
		$(EMACS) $(EMACSFLAGS) -f batch-byte-compile $$file 2>&1 | grep -v "^Wrote " || true; \
	done
	@echo "编译完成。"

# 字节编译文件列表
ELC_FILES = $(EL_FILES:.el=.elc)

# 测试目标
.PHONY: test
test: $(TEST_FILE)
	@echo "运行测试..."
	@$(ERT) -l $(TEST_FILE) -f ert-run-tests-batch-and-exit
	@echo "测试完成。"

.PHONY: test-interactive
test-interactive: $(TEST_FILE)
	@echo "启动交互式测试环境..."
	@$(EMACS) -l $(TEST_FILE) -f ert-run-tests-interactively

# 检查语法
.PHONY: check-syntax
check-syntax: $(EL_FILES)
	@echo "检查语法..."
	@for file in $(EL_FILES); do \
		echo "检查 $$file..."; \
		$(EMACS) $(EMACSFLAGS) --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile $$file 2>&1 | grep -v "^Wrote " || true; \
	done
	@echo "语法检查完成。"

# 清理目标
.PHONY: clean
clean:
	@echo "清理编译文件..."
	@rm -f $(ELC_FILES)
	@echo "清理完成。"

.PHONY: distclean
distclean: clean
	@echo "深度清理..."
	@rm -f *~ .*~ \#*\# .\#*
	@echo "深度清理完成。"

# 安装目标
.PHONY: install
install: compile
	@echo "安装到 $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	@cp $(EL_FILES) $(ELC_FILES) $(README_FILE) $(LICENSE_FILE) $(INSTALL_DIR)/
	@if [ -d "$(IMAGES_DIR)" ]; then \
		cp -r $(IMAGES_DIR) $(INSTALL_DIR)/; \
	fi
	@echo "安装完成。"

.PHONY: uninstall
uninstall:
	@echo "卸载 $(INSTALL_DIR)..."
	@rm -rf $(INSTALL_DIR)
	@echo "卸载完成。"

# 打包目标
.PHONY: dist
dist: clean
	@echo "创建发布包..."
	@mkdir -p dist
	@tar -czf dist/$(PACKAGE_NAME)-$(VERSION).tar.gz \
		--transform="s,^,$(PACKAGE_NAME)-$(VERSION)/," \
		$(EL_FILES) $(README_FILE) $(LICENSE_FILE) $(TEST_FILE) Makefile \
		$(if $(wildcard $(IMAGES_DIR)),$(IMAGES_DIR))
	@echo "发布包创建完成：dist/$(PACKAGE_NAME)-$(VERSION).tar.gz"

# 开发目标
.PHONY: dev
dev:
	@echo "启动开发环境..."
	@$(EMACS) -l achive.el &

# 文档目标
.PHONY: doc
doc: $(README_FILE)
	@echo "生成文档..."
	@$(EMACS) $(EMACSFLAGS) $(README_FILE) --eval "(org-html-export-to-html)" 2>/dev/null || true
	@echo "文档生成完成：$(README_FILE:.org=.html)"

# 帮助目标
.PHONY: help
help:
	@echo "achive Makefile 使用说明"
	@echo "========================"
	@echo ""
	@echo "编译和安装:"
	@echo "  make all        - 编译并运行测试（默认）"
	@echo "  make compile    - 编译所有 .el 文件"
	@echo "  make install    - 安装到 Emacs 目录"
	@echo "  make uninstall  - 卸载"
	@echo ""
	@echo "测试:"
	@echo "  make test       - 运行所有测试"
	@echo "  make test-interactive - 交互式运行测试"
	@echo ""
	@echo "代码质量:"
	@echo "  make check-syntax - 检查语法"
	@echo ""
	@echo "清理:"
	@echo "  make clean      - 清理编译文件"
	@echo "  make distclean  - 深度清理"
	@echo ""
	@echo "发布:"
	@echo "  make dist       - 创建发布包"
	@echo ""
	@echo "开发:"
	@echo "  make dev        - 启动开发环境"
	@echo "  make doc        - 生成 HTML 文档"
	@echo ""
	@echo "配置变量:"
	@echo "  EMACS=$(EMACS)"
	@echo "  EMACSFLAGS=$(EMACSFLAGS)"
	@echo "  INSTALL_DIR=$(INSTALL_DIR)"
	@echo ""

# 文件依赖
achive.elc: achive.el achive-utils.el
achive-utils.elc: achive-utils.el

# 特殊目标
.SILENT: help
.ONESHELL: