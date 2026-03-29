;;; achive.el --- A-stocks real-time data  -*- lexical-binding: t; -*-

;; Copyright (C) 2017 zakudriver

;; Author: zakudriver <zy.hua1122@gmail.com>
;; URL: https://github.com/zakudriver/achive
;; Version: 1.0
;; Package-Requires: ((emacs "25.2"))
;; Keywords: tools

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

;; Achive is a plug-in based on api of Sina that creates a dashboard displaying real-time data of a-share indexs and stocks.
;; Thanks for the super-fast Sina api, and achive performs so well to update data automatically.

;;; Code:

;;;; Requirements

(require 'cl-lib)
(require 'url)


(defvar url-http-response-status 0)

;;;; Customization

(defgroup achive nil
  "Settings for `achive'."
  :prefix "achive-"
  :group 'utils)


(defcustom achive-index-list '("sh000001" "sz399001" "sz399006")
  "List of composite index."
  :group 'achive
  :type 'list)


(defcustom achive-stock-list '("sh600036" "sz000625")
  "List of stocks."
  :group 'achive
  :type 'list)


(defcustom achive-buffer-name "*A Chive*"
  "Buffer name of achive board."
  :group 'achive
  :type 'string)

(defcustom achive-search-buffer-name "*A Chive - results -*"
  "Buffer name of achive search board."
  :group 'achive
  :type 'string)


(defcustom achive-auto-refresh t
  "Whether to refresh automatically."
  :group 'achive
  :type 'boolean)


(defcustom achive-refresh-seconds 5
  "Seconds of automatic refresh time."
  :group 'achive
  :type 'integer)


(defcustom achive-cache-path (concat user-emacs-directory ".achive")
  "Path of cache."
  :group 'achive
  :type 'string)


(defcustom achive-colouring t
  "Whether to apply face.
If it's nil will be low-key, you can peek at it at company time."
  :group 'achive
  :type 'string)

;;;;; faces

(defface achive-face-up
  '((t (:inherit (error))))
  "Face used when share prices are rising."
  :group 'achive)


(defface achive-face-down
  '((t :inherit (success)))
  "Face used when share prices are dropping."
  :group 'achive)


(defface achive-face-constant
  '((t :inherit (shadow)))
  "Face used when share prices are dropping."
  :group 'achive)


(defface achive-face-index-name
  '((t (:inherit (font-lock-keyword-face bold))))
  "Face used for index name."
  :group 'achive)

;;;; constants

(defconst achive-api "https://hq.sinajs.cn"
  "Stocks Api.")


(defconst achive-field-index-list
  '((code . 0) (name . achive-make-name) (price . 4) (change-percent . achive-make-change-percent)
    (high . 5) (low . 6) (volume . achive-make-volume) (turn-volume . achive-make-turn-volume) (open . 2) (yestclose . 3))
  "Index or fucntion of each piece of data.")


(defmacro achive-number-sort (index)
  "Create value of number sorting by INDEX."
  `(lambda (a b)
     (let ((get-percent-number (lambda (arg)
                                 (string-to-number (aref (cadr arg) ,index)))))
       (> (funcall get-percent-number a) (funcall get-percent-number b)))))

(defconst achive-visual-columns (vector
                                 '("股票代码" 8 nil)
                                 '("名称" 10 nil)
                                 (list "当前价" 10 (achive-number-sort 2))
                                 (list "涨跌幅" 7 (achive-number-sort 3))
                                 (list "最高价" 10 (achive-number-sort 4))
                                 (list "最低价" 10 (achive-number-sort 5))
                                 (list "成交量" 10 (achive-number-sort 6))
                                 (list "成交额" 10 (achive-number-sort 7))
                                 (list "开盘价" 10 (achive-number-sort 8))
                                 (list "昨日收盘价" 10 (achive-number-sort 9)))
  "Realtime board columns.")

;;;;; variables

(defvar achive-prev-point nil
  "Point of before render.")


(defvar achive-search-codes nil
  "Search code list.")


(defvar achive-stocks nil
  "Realtime stocks code list.")


(defvar achive-pop-to-buffer-action nil
  "Action to use internally when `pop-to-buffer' is called.")


(defvar achive-entry-list nil
  "Cache data for manual render.")

;;;;; functions

(defun achive-make-percent (price yestclose open)
  "Get stocks percent by (PRICE - YESTCLOSE) / YESTCLOSE, Return \"+/- xx%\".
If OPEN is \"0.00\", percent just is 0.00%."
  (if (zerop open)
      "0.00%"
    (unless (floatp price)
      (setq price (float price)))
    (unless (floatp yestclose)
      (setq yestclose (float yestclose)))
    (let ((result (/ (- price yestclose)
                     (if (zerop yestclose)
                         1.0 yestclose))))
      (format "%s%0.2f%%" (if (> result 0) "+" "") (* result 100)))))


(defmacro achive-set-timeout (callback seconds)
  "Like `setTimeout' for javascript.
CALLBACK: callback function.
SECONDS: integer of seconds."
  `(let ((timer))
     (setq timer (run-with-timer ,seconds nil (lambda ()
                                                (cancel-timer timer)
                                                (funcall ,callback timer))))))


(defun achive-time-list-index (word)
  "Get index of time list by WORD."
  (let ((words '("seconds" "minutes" "hour" "day" "month" "year" "dow" "dst" "zone")))
    (cl-position word words :test 'equal)))


(defun achive-decoded-time (time word)
  "Like decoded-time-xxx(Emacs '27.1').
Get TIME object item by WORD."
  (nth (achive-time-list-index word) time))


(defun achive-time-number (str)
  "STR of '12:00' to integer of 1200."
  (if (stringp str)
      (string-to-number (replace-regexp-in-string (regexp-quote ":") "" str))
    0))


(defun achive-hhmm-to-time (hhmm &optional func)
  "Convert HHMM to time.
Callback FUNC is handle to time list."
  (if (stringp hhmm)
      (setq hhmm (achive-time-number hhmm)))
  (let* ((now (decode-time))
         (time-code (list 0 (% hhmm 100) (/ hhmm 100)
                          (achive-decoded-time now "day")
				          (achive-decoded-time now "month")
                          (achive-decoded-time now "year")
                          (achive-decoded-time now "zone"))))
    (if (functionp func)
        (setq time-code (funcall func time-code)))
    (apply #'encode-time time-code)))


(defun achive-compare-time (hhmm)
  "Compare now and HHMM.
If now less than time return t."
  (let ((now (current-time))
        (time (achive-hhmm-to-time hhmm)))
    (time-less-p now time)))


(defun achive-readcache (path)
  "Read cache file of stock codes.
PATH: path of file dir."
  (if (file-exists-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (read (current-buffer)))))


(defun achive-writecache (path codes)
  "Write stock codes to cache file.
PATH: path of file dir.
CODES: list of stock codes."
  (with-temp-file path
    (prin1 codes (current-buffer))))


(defun achive-remove-nth-element (list index)
  "Remove LIST element by INDEX."
  (if (< (length list) (1+ index))
      nil
    (if (zerop index) (cdr list)
      (let ((last (nthcdr (1- index) list)))
        (setcdr last (cddr last))
        list))))


(defun achive-make-name (list _fields)
  "Make stock name by decode `gb18030'.
LIST: list of a stock value.
FIELDS: list of field index."
  (decode-coding-string (nth 1 list) 'gb18030))


(defun achive-make-change-percent (list fields)
  "Call function `achive-make-percent' to make `change-percent'.
LIST: list of a stock value.
FIELDS: list of field index."
  (achive-make-percent (string-to-number (nth (cdr (assoc 'price fields)) list))
                       (string-to-number (nth (cdr (assoc 'yestclose fields)) list))
                       (string-to-number (nth (cdr (assoc 'open fields)) list))))


(defun achive-make-volume (list _fields)
  "Get volume of display, current volume / 100.
LIST: list of a stock value.
FIELDS: list of field index."
  (number-to-string (/ (string-to-number (nth 9 list)) 100)))


(defun achive-make-turn-volume (list _fields)
  "Get turn-volume of display, current turn-volume / 10000, unit W (10000).
LIST: list of a stock value.
FIELDS: list of field index."
  (format "%dW" (/ (string-to-number (nth 10 list)) 10000)))

(defun achive-valid-entry-p (entry)
  "Check ENTRY data of valid.
ENTRY can be either (CODE DATA) list or data vector."
  (condition-case nil
      (if (vectorp entry)
          (not (string= (aref entry 1) "-"))
        (not (string= (aref (cadr entry) 1) "-")))
    (error nil)))


(defun achive-working-time-p (buffer-name)
  "判断是否为交易时间。
如果当前时间在任一市场的交易时间内，且名为 BUFFER-NAME 的缓冲区存在，
返回 t。否则返回 nil。"
  (if (get-buffer-window buffer-name)
      (let ((codes (append (bound-and-true-p achive-index-list)
                           (bound-and-true-p achive-stocks))))
        (cl-loop for code in codes
                 for market = (achive-get-market code)
                 when (and market (achive-market-trading-hours-p market))
                 return t))
    nil))

(defun achive-weekday-p ()
  "Whether it is weekend or not."
  (let ((week (format-time-string "%w")))
    (not (or (string= week "0") (string= week "6")))))

(defun achive-get-market (code)
  "根据股票代码识别市场。
CODE: 股票代码，如 sh000001, hk00700, usAAPL。
返回市场标识：a-share, hk, us 或 nil。"
  (cond
   ((string-match-p "^\\(sh\\|sz\\)" code) 'a-share)
   ((string-match-p "^hk" code) 'hk)
   ((string-match-p "^us" code) 'us)
   (t nil)))

(defun achive-market-trading-hours-p (market)
  "判断指定市场当前是否为交易时间。
MARKET: 市场标识：a-share, hk, us。
返回 t 如果在交易时间内，否则返回 nil。"
  (let* ((current-hour (string-to-number (format-time-string "%H")))
         (current-minute (string-to-number (format-time-string "%M")))
         (current-time-num (+ (* current-hour 100) current-minute)))
    (cl-case market
      (a-share
       (or (and (>= current-time-num 900) (<= current-time-num 1130))
           (and (>= current-time-num 1300) (<= current-time-num 1500))))
      (hk
       (or (and (>= current-time-num 930) (<= current-time-num 1200))
           (and (>= current-time-num 1300) (<= current-time-num 1600))))
      (us
       (let* ((utc-hour (string-to-number (format-time-string "%H" (current-time) t)))
              (est-hour (mod (- utc-hour 5) 24))  ; UTC-5 为美国东部时间
              (est-time-num (+ (* est-hour 100) current-minute)))
         (and (>= est-time-num 2130) (<= est-time-num 400))))
      (t nil))))


(defun achive-remove-face (faced)
  "Remove face for FACED to extract text."
  (let ((end (length faced)))
    (set-text-properties 0 end nil faced)
    faced))

(defun achive-make-request-url (api parameter)
  "Make sina request url.
API: shares api.
PARAMETER: request url parameter."
  (let ((normalized-codes (seq-filter #'identity (mapcar #'achive-normalize-code parameter))))
    (if normalized-codes
        (format "%s/list=%s" api (string-join normalized-codes ","))
      (error "没有有效的股票代码"))))

(defun achive-normalize-code (code)
  "标准化股票代码格式。
新浪API对美股使用 gb_ 前缀，但用户可能输入 us 前缀。
将 us 前缀转换为 gb_ 前缀，并转换为小写。
如果 CODE 为 nil 或空字符串，返回 nil。
对明显无效的代码（如纯数字）返回 nil。"
  (when (and code (stringp code) (not (string-empty-p code)))
    (let ((code (downcase (string-trim code))))
      ;; 检查是否包含至少一个字母（A股、港股、美股代码都包含字母）
      (if (string-match-p "[a-z]" code)
          (if (string-match "^us\\(.+\\)" code)
              (concat "gb_" (match-string 1 code))
            code)
        ;; 纯数字代码无效
        nil))))


(defun achive-request (url callback)
  "Handle request by URL.
  CALLBACK: function of after response."
  (let ((url-request-method "GET")  ; 改为GET方法
        (url-request-extra-headers '(("Content-Type" . "application/javascript;charset=UTF-8")
                                     ("Referer" . "https://finance.sina.com.cn")
                                     ("User-Agent" . "Mozilla/5.0"))))
    (url-retrieve url (lambda (status)
                        (let ((inhibit-message t))
                          (if (and (listp status) (plist-get status :error))
                              (message "achive: 请求失败: %s" (plist-get status :error))
                            (message "achive: %s at %s" "请求成功" (format-time-string "%T")))
                          (funcall callback)) nil 'silent))))


(defun achive-parse-response ()
  "Parse sina http response result by body."
  ;; 检查HTTP响应状态
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
        (let ((status-code (string-to-number (match-string 1))))
          (if (/= status-code 200)
              (error "Internal Server Error (状态码: %s)" status-code)))
      ;; 如果没有找到HTTP头，可能是直接的数据响应
      (message "achive: 警告: 未找到标准HTTP响应头，尝试直接解析")))

  (let ((resp-gbcode (with-current-buffer (current-buffer)
                       (buffer-substring-no-properties
                        (if (search-forward "\n\n" nil t)
                            (point)
                          (point-min))
                        (point-max)))))
    (let ((decoded-str (decode-coding-string resp-gbcode 'gb18030)))
      ;; 检查是否包含错误响应
      (when (string-match "sys_auth=\"FAILED\"" decoded-str)
        (error "API请求失败: 包含无效代码或参数"))
      decoded-str)))


(defun achive-format-content (codes resp-str)
  "Format response string to buffer string.
RESP-STR: string of response body.
CODES: stocks list of request parameters.
Return index and stocks data."
  (let ((str-list '()))
    (dolist (it codes)
      (when (and it (not (string-empty-p it)))
        (let ((normalized-it (achive-normalize-code it)))
          (if (let ((case-fold-search t))
                (string-match (format "%s=\"\\([^\"]+\\)\"" normalized-it) resp-str))
              (push (format "%s,%s" it (match-string 1 resp-str)) str-list)
            (message "achive: 警告: 未找到代码 %s (标准化为 %s) 的数据" it normalized-it)
            (push it str-list)))))
    (setq str-list (nreverse str-list))
    (cl-loop for it in str-list
             with temp = nil
             do (setq temp (achive-format-row it))
             collect (list (nth 0 temp)
                           (apply 'vector temp)))))


(defun achive-format-row (row-str)
  "Format row content.
ROW-STR: string of row."
  (let ((value-list (split-string row-str ",")))
    (if (length= value-list 1)
        (progn
          (message "achive: 警告: 行数据仅包含一个字段: %s" row-str)
          (append value-list (make-list 9 "-")))
      (cl-loop for (_k . v) in achive-field-index-list
               collect (if (functionp v)
                           (funcall v value-list achive-field-index-list)
                         (if (< v (length value-list))
                             (nth v value-list)
                           (progn
                             (message "achive: 警告: 字段索引 %d 超出范围 (总字段数: %d)" v (length value-list))
                             "-")))))))


(defun achive-validate-request (codes callback)
  "Validate that the CODES is valid, then call CALLBACK function."
  (achive-request (achive-make-request-url achive-api codes)
                  (lambda ()
                    (condition-case err
                        (funcall callback (seq-filter
                                           #'achive-valid-entry-p
                                           (achive-format-content codes (achive-parse-response))))
                      (error (message "achive: 验证请求失败: %s" (error-message-string err))
                             (funcall callback nil))))))


(defun achive-render-request (buffer-name codes &optional callback)
  "Handle request by stock CODES, and render buffer of BUFFER-NAME.
CALLBACK: callback function after the rendering."
  (achive-request (achive-make-request-url achive-api codes)
                  (lambda ()
                    (condition-case err
                        (let ((entries (achive-format-content codes (achive-parse-response))))
                          (setq achive-entry-list entries)
                          (achive-render buffer-name)
                          (if (functionp callback)
                              (funcall callback entries)))
                      (error (message "achive: 渲染请求失败: %s" (error-message-string err))
                             (if (functionp callback)
                                 (funcall callback nil)))))))


(defun achive-render (buffer-name &optional manual)
  "Render visual buffer of BUFFER-NAME.
If MANUAL is t and `achive-colouring' is nil,
entry will remove face before render."
  (let ((entries (if achive-colouring
                     (mapcar #'achive-propertize-entry-face
                             achive-entry-list)
                   achive-entry-list)))

    (if (and manual (not achive-colouring))
        (setq entries (mapcar #'achive-remove-entry-face
                              achive-entry-list)))

    (with-current-buffer buffer-name
      (setq tabulated-list-entries entries)
      (tabulated-list-print t t))))


(defun achive-refresh ()
  "Referer achive visual buffer or achive search visual buffer."
  (if (get-buffer-window achive-buffer-name)
      (achive-render-request achive-buffer-name (append achive-index-list achive-stocks)))
  (if (get-buffer-window achive-search-buffer-name)
      (achive-render-request achive-search-buffer-name achive-search-codes)))


(defun achive-timer-alive-p ()
  "Check that the timer is alive."
  (get-buffer achive-buffer-name))


(defun achive-switch-visual (buffer-name)
  "Switch to visual buffer by BUFFER-NAME."
  (pop-to-buffer buffer-name achive-pop-to-buffer-action)
  (achive-visual-mode))


(defun achive-loop-refresh (_timer)
  "Loop to refresh."
  (if (and (achive-timer-alive-p) (achive-weekday-p))
      (if (achive-working-time-p achive-buffer-name)
          (achive-render-request achive-buffer-name
                                 (append achive-index-list achive-stocks)
                                 (lambda (_resp)
                                   (achive-handle-auto-refresh)))
        (achive-handle-auto-refresh))))


(defun achive-handle-auto-refresh ()
  "Automatic refresh."
  (achive-set-timeout #'achive-loop-refresh
                      achive-refresh-seconds))


(defun achive-init ()
  "Init program. Read cache codes from file."
  (let ((cache (achive-readcache achive-cache-path)))
    (unless cache
      (achive-writecache achive-cache-path achive-stock-list)
      (setq cache achive-stock-list))
    ;; 过滤掉 nil 和空字符串
    (setq achive-stocks (seq-filter (lambda (code) (and code (not (string-empty-p code)))) cache))))


(defun achive-propertize-entry-face (entry)
  "Propertize ENTRY."
  (let* ((id (car entry))
         (data (cadr entry))
         (percent (aref data 3))
         (percent-number (string-to-number percent)))

    (when (cl-position id achive-index-list :test 'string=)
      (aset data 0 (propertize (aref data 0) 'face 'achive-face-index-name))
      (aset data 1 (propertize (aref data 1) 'face 'achive-face-index-name)))

    (aset data 3 (propertize percent 'face (cond
                                            ((> percent-number 0)
                                             'achive-face-up)
                                            ((< percent-number 0)
                                             'achive-face-down)
                                            (t 'achive-face-constant))))
    entry))


(defun achive-remove-entry-face (entry)
  "Remove ENTRY properties."
  (let* ((id (car entry))
         (data (cadr entry)))
    (when (cl-position id achive-index-list :test 'string=)
      (achive-remove-face (aref data 0))
      (achive-remove-face (aref data 1)))

    (achive-remove-face (aref data 3))
    entry))

;;;;; interactive

;;;###autoload
(defun achive ()
  "Launch achive and switch to visual buffer."
  (interactive)
  (achive-init)

  (let ((timer-alive (achive-timer-alive-p)))

    (achive-switch-visual achive-buffer-name)
    (achive-render-request achive-buffer-name
                           (append achive-index-list achive-stocks)
                           (lambda (_resp)
                             (if (and achive-auto-refresh (not timer-alive))
                                 (achive-handle-auto-refresh))))))

;;;###autoload
(defun achive-search (codes)
  "搜索股票代码并显示结果。
CODES: 股票代码字符串，多个代码用空格分隔。
搜索结果显示在独立缓冲区，不会自动添加到主列表。
使用 achive-add 命令将股票添加到主列表。"
  (interactive "s请输入要搜索的股票代码: ")
  (setq achive-search-codes (seq-filter (lambda (code) (and code (not (string-empty-p code)))) (split-string codes)))
  (if (null achive-search-codes)
      (message "请输入有效的股票代码")
    (achive-switch-visual achive-search-buffer-name)
    (achive-render-request achive-search-buffer-name achive-search-codes
                           (lambda (resp)
                             (unless resp
                               (message "未找到股票数据，请检查代码是否正确"))
                             (when resp
                               (message "搜索完成。使用 '+' 键添加当前股票到主列表，或使用 achive-add 命令添加多个代码。"))))))

;;;###autoload
(defun achive-current-code ()
  "获取当前行的股票代码。
如果在 `achive-visual-mode' 缓冲区中，返回当前行对应的股票代码字符串。
否则返回 nil。"
  (when (derived-mode-p 'achive-visual-mode)
    (let ((id (tabulated-list-get-id)))
      (when (and id (stringp id))
        id))))

(defun achive-add (codes)
  "添加股票代码到主列表。
不带前缀参数时，添加当前行的股票代码；带前缀参数时，提示输入股票代码（多个代码用空格分隔）。"
  (interactive (list (if current-prefix-arg
                         (read-string "请输入要添加的股票代码: ")
                       (or (achive-current-code)
                           (read-string "请输入要添加的股票代码: ")))))
  (setq codes (seq-filter (lambda (code) (and code (not (string-empty-p code)))) (split-string codes)))
  (if (null codes)
      (message "请输入有效的股票代码")
    (achive-validate-request codes (lambda (resp)
                                     (if resp
                                         (let ((valid-codes (mapcar #'car resp)))
                                           (when valid-codes
                                             (setq achive-stocks (append achive-stocks valid-codes))
                                             (achive-writecache achive-cache-path achive-stocks)
                                             (achive-render-request achive-buffer-name
                                                                    (append achive-index-list achive-stocks)
                                                                    (lambda (_resp)
                                                                      (message "已添加: [%s]"
                                                                               (mapconcat 'identity valid-codes ", "))))))
                                       (message "未找到有效的股票代码"))))))

;;;###autoload
(defun achive-remove ()
  "Remove stocks."
  (interactive)
  (let* ((code (completing-read "Please select the stock code to remove: "
                                achive-stocks
                                nil
                                t
                                nil
                                nil
                                nil))
         (index (cl-position code achive-stocks :test 'string=)))
    (when index
      (setq achive-stocks (achive-remove-nth-element achive-stocks index))
      (achive-writecache achive-cache-path achive-stocks)
      (achive-render-request achive-buffer-name (append achive-index-list achive-stocks)
                             (lambda (_resp)
                               (message "<%s> have been removed." code))))))


(defun achive-show-chart (&optional chart-type)
  "展示当前行股票的走势图。
CHART-TYPE: 图表类型，'daily 为日线图，'min 为分时图，默认为日线图。"
  (interactive)
  (let* ((code (achive-current-code)))
    (if (and code (stringp code))
        (let* ((normalized-code (achive-normalize-code code)))
          (if normalized-code
              (let* ((chart-type (or chart-type 'daily))
                     (chart-suffix (if (eq chart-type 'daily) "daily" "min"))
                     (url (format "http://image.sinajs.cn/newchart/%s/n/%s.gif" chart-suffix normalized-code))
                     (buffer-name (format "*A Chive - %s Chart - %s*" (if (eq chart-type 'daily) "Daily" "Min") code)))
                (url-retrieve url
                              (lambda (status)
                                (let ((inhibit-message t))
                                  (if (and (listp status) (plist-get status :error))
                                      (message "achive: 获取走势图失败: %s" (plist-get status :error))
                                    (with-current-buffer (current-buffer)
                                      (goto-char (point-min))
                                      (if (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
                                          (let ((status-code (string-to-number (match-string 1))))
                                            (if (= status-code 200)
                                                (progn
                                                  (let ((image-data (buffer-substring-no-properties
                                                                     (if (search-forward "\n\n" nil t)
                                                                         (point)
                                                                       (point-min))
                                                                     (point-max))))
                                                    (kill-buffer)
                                                    (with-current-buffer (get-buffer-create buffer-name)
                                                      (erase-buffer)
                                                      (insert-image (create-image image-data 'gif t))
                                                      (image-mode)
                                                      (goto-char (point-min))
                                                      (pop-to-buffer (current-buffer))))
                                                  (message "achive: 获取走势图失败 (状态码: %s)" status-code))
                                              (message "achive: 获取走势图失败: 无效的HTTP响应")))))))))
                (message "achive: 无效的股票代码: %s" code)))
          (message "achive: 请先选择一个股票")))))

;;;###autoload
(defun achive-show-daily-chart ()
  "展示当前行股票的日线图。"
  (interactive)
  (achive-show-chart 'daily))

;;;###autoload
(defun achive-show-min-chart ()
  "展示当前行股票的分时图。"
  (interactive)
  (achive-show-chart 'min))

;;;###autoload
(defun achive-switch-colouring ()
  "Manual switch colouring. It's handy for emergencies."
  (interactive)
  (setq achive-colouring (not achive-colouring))
  (achive-render (buffer-name) t))

;;;;; mode
(defvar achive-visual-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "+" 'achive-add)
    (define-key map "-" 'achive-remove)
    (define-key map "c" 'achive-switch-colouring)
    (define-key map "d" 'achive-show-daily-chart)
    (define-key map "m" 'achive-show-min-chart)
    map)
  "Keymap for `achive-visual-mode'.")


(define-derived-mode achive-visual-mode tabulated-list-mode "Achive"
  "Major mode for avhice real-time board."
  (setq tabulated-list-format achive-visual-columns)
  (setq tabulated-list-sort-key nil)
  (add-hook 'tabulated-list-revert-hook 'achive-refresh nil t)
  (tabulated-list-init-header)
  (tablist-minor-mode))


(provide 'achive)

;;; achive.el ends here

;; 0：”大秦铁路”，股票名字；
;; 1：”27.55″，今日开盘价；
;; 2：”27.25″，昨日收盘价；
;; 3：”26.91″，当前价格；
;; 4：”27.55″，今日最高价；
;; 5：”26.20″，今日最低价；
;; 6：”26.91″，竞买价，即“买一”报价；
;; 7：”26.92″，竞卖价，即“卖一”报价；
;; 8：”22114263″，成交的股票数，由于股票交易以一百股为基本单位，所以在使用时，通常把该值除以一百；
;; 9：”589824680″，成交金额，单位为“元”，为了一目了然，通常以“万元”为成交金额的单位，所以通常把该值除以一万；
;; 10：”4695″，“买一”申请4695股，即47手；
;; 11：”26.91″，“买一”报价；
;; 12：”57590″，“买二”
;; 13：”26.90″，“买二”
;; 14：”14700″，“买三”
;; 15：”26.89″，“买三”
;; 16：”14300″，“买四”
;; 17：”26.88″，“买四”
;; 18：”15100″，“买五”
;; 19：”26.87″，“买五”
;; 20：”3100″，“卖一”申报3100股，即31手；
;; 21：”26.92″，“卖一”报价
;; (22, 23), (24, 25), (26,27), (28, 29)分别为“卖二”至“卖四的情况”
;; 30：”2008-01-11″，日期；
;; 31：”15:05:32″，时间；

;; var hq_str_sh000001=\"上证指数,3261.9219,3268.6955,3245.3123,3262.0025,3216.9927,0,0,319906033,409976276121,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2023-03-14,15:30:39,00,\"

;; ("sh000001" "上证指数" "3245.3123" "-0.72%" "3262.0025" "3216.9927" 3199060 "40997627W" "3261.9219" "3268.6955")

;; var hq_str_sh603866=\"桃李面包,0.000,15.250,15.250,0.000,0.000,0.000,0.000,0,0.000,0,0.000,0,0.000,0,0.000,0,0.000,0,0.000,0,0.000,0,0.000,0,0.000,0,0.000,0,0.000,2023-03-27,09:11:30,00,\"

;; var hq_str_sh603866=\"桃李面包,0.000,15.250,15.250,0.000,0.000,15.110,15.110,0,0.000,5100,15.110,2000,0.000,0,0.000,0,0.000,0,0.000,5100,15.110,0,0.000,0,0.000,0,0.000,0,0.000,2023-03-27,09:16:00,00,\"

;; ("sh603866" ["sh603866" "桃李面包" "15.250" "0.00%" "0.000" "0.000" "0" "0W" "0.000" "15.250"])

;; http://image.sinajs.cn/newchart/daily/n/sh601006.gif
