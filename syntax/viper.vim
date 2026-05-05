if exists("b:current_syntax")
  finish
endif

" Keywords
syn keyword viperKeyword
      \ method function predicate field domain axiom
      \ import define
      \ var
      \ if else elseif while
      \ returns
      \ fold unfold
      \ inhale exhale
      \ assert assume
      \ goto label
      \ package applying
      \ new

syn keyword viperBoolean true false
syn keyword viperNull null

syn keyword viperType Int Bool Perm Ref Seq Set Multiset Map

syn keyword viperSpec
      \ requires ensures invariant
      \ forall exists
      \ acc wildcard write none epsilon
      \ unfolding in
      \ old result

" Operators and special tokens
syn match viperOperator /[+\-*\/|&!<>=~?:\.#@^]/
syn match viperOperator /==/
syn match viperOperator /!=/
syn match viperOperator /<=/
syn match viperOperator />=/
syn match viperOperator /&&/
syn match viperOperator /||/
syn match viperOperator /==>/
syn match viperOperator /<==>/
syn match viperOperator /--\*/
syn match viperOperator /-\*-/

" Numbers
syn match viperNumber /\<[0-9]\+\>/
syn match viperNumber /\<[0-9]*\.[0-9]\+\>/

" Strings
syn region viperString start=/"/ end=/"/ skip=/\\"/

" Comments
syn match viperComment "//.*$"
syn region viperComment start="/\*" end="\*/" fold

hi def link viperKeyword   Keyword
hi def link viperSpec      PreProc
hi def link viperType      Type
hi def link viperBoolean   Boolean
hi def link viperNull      Constant
hi def link viperOperator  Operator
hi def link viperNumber    Number
hi def link viperString    String
hi def link viperComment   Comment

let b:current_syntax = "viper"
