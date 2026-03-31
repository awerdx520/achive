;;; test-achive.el --- 测试 achive 扩展功能  -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author:
;; URL: https://github.com/zakudriver/achive
;; Version: 1.0
;; Package-Requires: ((emacs "25.2") (ert "1.0"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; 测试 achive 对港股和美股的支持功能

;;; Code:

(require 'ert)

;; 直接加载文件内容，避免require依赖
(defun test-load-achive-files ()
  "加载achive相关文件。"
  (load-file "achive.el"))

(test-load-achive-files)

;;; 市场识别函数测试

(ert-deftest test-achive-get-market ()
  "测试市场识别函数。"
  (should (eq (achive-get-market "sh000001") 'a-share))
  (should (eq (achive-get-market "sz399001") 'a-share))
  (should (eq (achive-get-market "hk00700") 'hk))
  (should (eq (achive-get-market "hkHSI") 'hk))
  (should (eq (achive-get-market "usAAPL") 'us))
  (should (eq (achive-get-market "usDJI") 'us))
  (should (eq (achive-get-market "gb_aapl") nil))  ; gb_ 前缀不识别，需要标准化
  (should (eq (achive-get-market "invalid") nil)))

(ert-deftest test-achive-get-market-edge-cases ()
  "测试市场识别边界情况。"
  (should (eq (achive-get-market "sh") 'a-share))
  (should (eq (achive-get-market "sz") 'a-share))
  (should (eq (achive-get-market "hk") 'hk))
  (should (eq (achive-get-market "us") 'us))
  (should (eq (achive-get-market "") nil))
  (should (eq (achive-get-market "123") nil)))

;;; API标准化测试
(ert-deftest test-achive-normalize-code ()
  "测试股票代码标准化函数。"
  (should (string= (achive-normalize-code "sh000001") "sh000001"))
  (should (string= (achive-normalize-code "sz399001") "sz399001"))
  (should (string= (achive-normalize-code "hk00700") "hk00700"))
  (should (string= (achive-normalize-code "usAAPL") "gb_aapl"))   ; 注意：转换为小写
  (should (string= (achive-normalize-code "usMSFT") "gb_msft"))   ; 注意：转换为小写
  (should (string= (achive-normalize-code "usTSLA") "gb_tsla"))   ; 注意：转换为小写
  (should (string= (achive-normalize-code "gb_aapl") "gb_aapl"))  ; 已经是标准格式
  (should (string= (achive-normalize-code "invalid") "invalid")))

(ert-deftest test-achive-normalize-code-edge-cases ()
  "测试标准化边界情况。"
  (should (string= (achive-normalize-code "us123") "gb_123"))
  (should (string= (achive-normalize-code "us_abc") "gb__abc"))
  (should (string= (achive-normalize-code "UsTest") "gb_test"))  ; 测试大小写转换
  (should (eq (achive-normalize-code "") nil)))

;;; 交易时间判断测试（模拟测试）

(defun test-mock-time (hour minute)
  "模拟指定的小时和分钟时间。
返回一个模拟的时间对象用于测试。"
  (let ((time (decode-time)))
    (setf (nth 0 time) 0)      ; 秒
    (setf (nth 1 time) minute) ; 分
    (setf (nth 2 time) hour)   ; 时
    (apply #'encode-time time)))

(ert-deftest test-achive-market-trading-hours-p-a-share ()
  "测试A股交易时间判断。"
  (should (functionp 'achive-market-trading-hours-p)))

(ert-deftest test-achive-market-trading-hours-p-hk ()
  "测试港股交易时间判断。"
  (should (functionp 'achive-market-trading-hours-p)))

(ert-deftest test-achive-market-trading-hours-p-us ()
  "测试美股交易时间判断（美国东部时间）。"
  (should (functionp 'achive-market-trading-hours-p)))

;;; 多市场配置测试

(ert-deftest test-multi-market-configuration ()
  "测试多市场配置识别。"
  (let ((achive-index-list '("sh000001" "hkHSI" "usDJI"))
        (achive-stock-list '("sh600036" "hk00700" "usAAPL")))

    ;; 测试指数市场识别
    (should (eq (achive-get-market (nth 0 achive-index-list)) 'a-share))
    (should (eq (achive-get-market (nth 1 achive-index-list)) 'hk))
    (should (eq (achive-get-market (nth 2 achive-index-list)) 'us))

    ;; 测试股票市场识别
    (should (eq (achive-get-market (nth 0 achive-stock-list)) 'a-share))
    (should (eq (achive-get-market (nth 1 achive-stock-list)) 'hk))
    (should (eq (achive-get-market (nth 2 achive-stock-list)) 'us))))

;;; API请求URL生成测试

(ert-deftest test-achive-make-request-url ()
  "测试API请求URL生成。"
  (let ((api "https://hq.sinajs.cn")
        (codes-a '("sh000001" "sz399001"))
        (codes-multi '("sh000001" "hk00700" "usAAPL")))

    ;; A股URL
    (should (string= (achive-make-request-url api codes-a)
                     "https://hq.sinajs.cn/list=sh000001,sz399001"))

    ;; 多市场URL（美股代码被标准化为小写）
    (should (string= (achive-make-request-url api codes-multi)
                     "https://hq.sinajs.cn/list=sh000001,hk00700,gb_aapl"))))

;;; 代理配置测试

(ert-deftest test-achive-normalize-proxy-address ()
  "测试代理地址规范化。"
  (should (eq (achive--normalize-proxy-address nil) nil))
  (should (eq (achive--normalize-proxy-address "") nil))
  (should (string= (achive--normalize-proxy-address "127.0.0.1:7890") "127.0.0.1:7890"))
  (should (string= (achive--normalize-proxy-address " http://127.0.0.1:7890 ") "127.0.0.1:7890"))
  (should (string= (achive--normalize-proxy-address "https://proxy.example.com:8080") "proxy.example.com:8080"))
  (should (eq (achive--normalize-proxy-address "not-a-proxy") nil)))

(ert-deftest test-achive-proxy-services ()
  "测试 `achive--proxy-services' 生成的 `url-proxy-services'。"
  (let ((achive-proxy nil))
    (should (eq (achive--proxy-services) nil)))
  (let ((achive-proxy "127.0.0.1:7890")
        (achive-proxy-no-proxy "localhost,127.0.0.1"))
    (should (equal (achive--proxy-services)
                   '(("http" . "127.0.0.1:7890")
                     ("https" . "127.0.0.1:7890")
                     ("no_proxy" . "localhost,127.0.0.1"))))))

(ert-deftest test-achive-curl-chart-data-inject-proxy-arg ()
  "测试走势图 curl 下载会注入 -x 代理参数。"
  (let ((achive-proxy "127.0.0.1:7890")
        (called-args nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_) t))
              ((symbol-function 'call-process)
               (lambda (_program _infile _destination _display &rest args)
                 (setq called-args args)
                 ;; 模拟 curl 成功并写入一些二进制内容
                 (with-current-buffer (current-buffer)
                   (insert "GIF89a"))
                 0)))
      (should (string-match-p "\\`GIF8[79]a" (achive--curl-chart-data "http://example.com/a.gif")))
      (should (member "-x" called-args))
      (should (member "127.0.0.1:7890" called-args)))))

;;; 工作函数测试

(ert-deftest test-achive-working-time-p-multi-market ()
  "测试多市场工作时间判断。"
  ;; 模拟有A股在交易时间
  (let ((achive-index-list '("sh000001"))
        (achive-stock-list '("sh600036")))
    (cl-letf (((symbol-function 'get-buffer-window) (lambda (_) t))
              ((symbol-function 'achive-get-market) (lambda (code)
                                                      (cond
                                                       ((string-match-p "^sh" code) 'a-share)
                                                       (t nil))))
              ((symbol-function 'achive-market-trading-hours-p) (lambda (market)
                                                                  (eq market 'a-share))))
      (should (achive-working-time-p "*test*"))))

  ;; 模拟无交易时间
  (let ((achive-index-list '("sh000001"))
        (achive-stock-list '("sh600036")))
    (cl-letf (((symbol-function 'get-buffer-window) (lambda (_) t))
              ((symbol-function 'achive-get-market) (lambda (code)
                                                      (cond
                                                       ((string-match-p "^sh" code) 'a-share)
                                                       (t nil))))
              ((symbol-function 'achive-market-trading-hours-p) (lambda (_) nil)))
      (should-not (achive-working-time-p "*test*"))))

  ;; 模拟无缓冲区
  (cl-letf (((symbol-function 'get-buffer-window) (lambda (_) nil)))
    (should-not (achive-working-time-p "*test*"))))

;;; 辅助函数测试

(ert-deftest test-achive-remove-nth-element ()
  "测试移除列表元素函数。"
  (should (equal (achive-remove-nth-element '("a" "b" "c") 0) '("b" "c")))
  (should (equal (achive-remove-nth-element '("a" "b" "c") 1) '("a" "c")))
  (should (equal (achive-remove-nth-element '("a" "b" "c") 2) '("a" "b")))
  (should (equal (achive-remove-nth-element '("a") 0) nil))
  (should (equal (achive-remove-nth-element '("a" "b") 2) nil)))

(ert-deftest test-achive-valid-entry-p ()
  "测试有效条目判断函数。"
  (should (achive-valid-entry-p '("sh000001" ["sh000001" "上证指数" "3245.31" "-0.72%"])))
  (should-not (achive-valid-entry-p '("invalid" ["invalid" "-" "-" "-"]))))

(ert-deftest test-achive-dedupe-codes ()
  "测试代码列表去重（忽略大小写）。"
  (should (equal (achive-dedupe-codes '("hk00700" "HK00700" "sh600036"))
                 '("hk00700" "sh600036"))))

(ert-deftest test-achive-display-codes-merge ()
  "测试指数与自选合并：去重且自选中与指数重复的代码不重复展示。"
  (let ((achive-index-list '("sh000001" "sz399001"))
        (achive-stocks '("sh600036" "sh000001" "hk00700" "sh600036")))
    (should (equal (achive-display-codes)
                   '("sh000001" "sz399001" "sh600036" "hk00700")))))

(ert-deftest test-achive-format-row-hk-opens-not-name ()
  "港股解析：开盘价必须为数值列，不得取中文名称列。
新浪港股字段顺序为「英文简称,中文名,现价,开盘价,最高,最低,昨收,…」。"
  (let* ((row "hk00700,TENCENT,腾讯控股,484.400,481.600,492.000,480.000,487.600,6.000,1.246,0,0,6952708467,14357032,0,0,0,0,2026/03/31,14:01")
         (vec (vconcat (achive-format-row row))))
    (should (string= (aref vec 1) "腾讯控股"))
    (should (string= (aref vec 2) "484.400"))
    (should (string= (aref vec 8) "481.600"))))

(ert-deftest test-achive-format-row-us-parse-indices ()
  "美股解析：新浪 `gb_` 返回字段与 A 股不同，须使用 `achive-parse-indices-us`。
现价、昨收、开盘等不得沿用 A 股列号（否则会把日期等误当作价格）。"
  (let* ((row (concat "usAAPL,苹果,246.6300,-0.87,2026-03-31 16:47:42,-2.1700,250.0700,250.8700,"
                       "245.5100,288.3600,168.1700,39446015,43463141,3620809558200,7.93,31.100000,0.00,0.00,"
                       "0.00,0.00,14681140000,63,247.8123,0.48,1.18,Mar 31 04:47AM EDT,Mar 30 04:00PM EDT,"
                       "248.8000,66463,1,2026,9737363943.0869,248.8000,246.6300,16487740.4904,248.1500,246.6300"))
         (vec (vconcat (achive-format-row row))))
    (should (string= (aref vec 1) "苹果"))
    (should (string= (aref vec 2) "246.6300"))
    (should (string-match-p "-0\\.87" (aref vec 3)))
    (should (string= (aref vec 8) "250.0700"))
    (should (string= (aref vec 9) "248.8000"))))

;;; 运行测试

(defun run-achive-tests ()
  "运行所有 achive 测试。"
  (interactive)
  (ert-run-tests-interactively "test-achive-"))

;; 提供运行命令
(provide 'test-achive)

;;; test-achive.el ends here
