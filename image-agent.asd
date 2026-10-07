(asdf:defsystem "image-agent"
  :description "Resumable, cooperative live SBCL image repair"
  :license "MIT"
  :version "0.1.0" :serial t :components ((:file "src/kernel") (:file "src/properties")))
(asdf:defsystem "image-agent/store"
  :license "MIT"
  :depends-on ("image-agent") :serial t
  :components ((:file "src/store") (:file "src/reference-world")))
(asdf:defsystem "image-agent/openai"
  :license "MIT"
  :depends-on ("image-agent" "dexador" "yason" "babel")
  :components ((:file "src/openai")))
(asdf:defsystem "image-agent/cli"
  :license "MIT"
  :depends-on ("image-agent/store" "image-agent/openai") :serial t
  :components ((:file "src/tools") (:file "src/chat") (:file "src/context") (:file "src/cli")))
(asdf:defsystem "image-agent/terminal"
  :license "MIT"
  :depends-on ("image-agent/cli") :components ((:file "src/terminal")))
(asdf:defsystem "image-agent/experiments"
  :license "MIT"
  :depends-on ("image-agent/cli")
  :components ((:file "src/experiments")))
(asdf:defsystem "image-agent/tests"
  :license "MIT"
  :depends-on ("image-agent/store" "image-agent/experiments" "fiveam" "check-it")
  :serial t :components ((:file "tests/suite") (:file "tests/cli-suite") (:file "tests/experiment-suite") (:file "tests/composition-suite") (:file "tests/context-suite")))
