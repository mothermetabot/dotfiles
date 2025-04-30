# enable statship
eval "$(starship init zsh)"

# Append aliases 
source ./.shell/aliases.zsh

# Append variables
source ./.shell/var.zsh

# append .local/bin
PATH=/home/esguio/.local/bin:$PATH
export PATH
