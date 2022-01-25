#!/usr/bin/env bash

source ./mo
diff <(moUsage) <((moDeclare; echo moUsage) | bash)
