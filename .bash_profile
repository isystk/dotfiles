# .bash_profile の中身は .bashrc を読み込むだけにする
if [ -f ~/.bashrc ] ; then
. ~/.bashrc
fi
