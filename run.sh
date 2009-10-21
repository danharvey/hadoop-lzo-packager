#!/bin/bash -e
set -x

##############################
# Begin configurables
##############################
# Which project to build.
#   github - builds the github fork hadoop-lzo project
#   googlecode - builds the original google code repo
SRC_PROJECT=${SRC_PROJECT:-github}

RELEASE=${RELEASE:-1}

# Some metadata fields for the packages (used only by rpms)
PACKAGER=${PACKAGER:-$(getent passwd $USER | cut -d':' -f5 | cut -d, -f1)}
HOST=${HOST:-$(hostname -f)}
PACKAGER_EMAIL=${PACKAGER_EMAIL:-$USER@$HOST}

# The hadoop home that the packages will eventually install into
# TODO(todd) this is currently only used by rpms, I believe
HADOOP_HOME=${HADOOP_HOME:-/usr/lib/hadoop-0.20}
##############################
# End configurables
##############################
BINDIR=$(readlink -f $(dirname $0))
mkdir -p build

setup_googlecode() {
    SVNURL=${SVNURL:-http://hadoop-gpl-compression.googlecode.com/svn/trunk/}
    PACKAGE_HOMEPAGE=http://code.google.com/p/hadoop-gpl-compression/
    if [ -z "$SVN_REV" ]; then
        SVN_REV=$(svn info $SVNURL | grep Revision | awk '{print $2}')
        [[ $SVN_REV == [0-9]+ ]]
        echo "SVN Revision: $SVN_REV"
    fi
    VERSION=${VERSION:-0.2.0svn$SVN_REV}
    NAME=hadoop-gpl-compression
}

checkout_googlecode() {
    if [ ! -d $CHECKOUT ]; then
        svn export -r $SVN_REV $SVNURL $CHECKOUT
    fi
    CHECKOUT_TAR=$BINDIR/build/${NAME}-$VERSION.tar.gz
}

setup_github() {
    GITHUB_ACCOUNT=${GITHUB_ACCOUNT:-toddlipcon}
    GITHUB_BRANCH=${GITHUB_BRANCH:-master}
    PACKAGE_HOMEPAGE=http://github.com/$GITHUB_ACCOUNT/hadoop-lzo
    TARURL=http://github.com/$GITHUB_ACCOUNT/hadoop-lzo/tarball/$GITHUB_BRANCH
    if [ -z "$(ls $BINDIR/build/$GITHUB_ACCOUNT-hadoop*tar.gz)" ]; then
        wget -P $BINDIR/build/ $TARURL
    fi
    ORIG_TAR=$(ls -1 $BINDIR/build/$GITHUB_ACCOUNT-hadoop*tar.gz | head -1)
    GIT_HASH=$(expr match $ORIG_TAR ".*hadoop-lzo-\(.*\).tar.gz")
    echo "Git hash: $GIT_HASH"
    NAME=$GITHUB_ACCOUNT-hadoop-lzo
    VERSION=$(date +"%Y%m%d%H%M%S").$GIT_HASH

    pushd $BINDIR/build/ > /dev/null
    mkdir $NAME-$VERSION/
    tar -C $NAME-$VERSION/ --strip-components=1 -xzf $ORIG_TAR
    tar czf $NAME-$VERSION.tar.gz $NAME-$VERSION/
    popd > /dev/null

    CHECKOUT_TAR=$BINDIR/build/$NAME-$VERSION.tar.gz
}

checkout_github() {
    echo -n
}

do_substs() {
sed "
 s,@PACKAGE_NAME@,$NAME,g;
 s,@PACKAGE_HOMEPAGE@,$PACKAGE_HOMEPAGE,g;
 s,@VERSION@,$VERSION,g;
 s,@RELEASE@,$RELEASE,g;
 s,@PACKAGER@,$PACKAGER,g;
 s,@PACKAGER_EMAIL@,$PACKAGER_EMAIL,g;
 s,@HADOOP_HOME@,$HADOOP_HOME,g;
"
}

setup_$SRC_PROJECT

TOPDIR=$BINDIR/build/topdir

CHECKOUT=$BINDIR/${NAME}-$VERSION
checkout_$SRC_PROJECT


if [ ! -e $CHECKOUT_TAR ]; then
  pushd $CHECKOUT
  cd ..
  tar czf $CHECKOUT_TAR $(basename $CHECKOUT)
  popd
fi

##############################
# RPM
##############################
if [ -z "$SKIP_RPM" ]; then
rm -Rf $TOPDIR
mkdir -p $TOPDIR

(cd $TOPDIR/ && mkdir SOURCES BUILD SPECS SRPMS RPMS BUILDROOT)

cat $BINDIR/template.spec | do_substs > $TOPDIR/SPECS/${NAME}.spec

cp $CHECKOUT_TAR $TOPDIR/SOURCES

pushd $TOPDIR/SPECS > /dev/null
rpmbuild $RPMBUILD_FLAGS \
  --buildroot $(pwd)/../BUILDROOT \
  --define "_topdir $(pwd)/.." \
  -ba ${NAME}.spec
popd
fi

##############################
# Deb
##############################
if [ -z "$SKIP_DEB" ]; then
DEB_DIR=$BINDIR/build/deb
mkdir -p $DEB_DIR
rm -Rf $DEB_DIR

mkdir $DEB_DIR
cp -a $CHECKOUT_TAR $DEB_DIR/${NAME}_$VERSION.orig.tar.gz
pushd $DEB_DIR
tar xzf *.tar.gz
cp -a $BINDIR/debian/ ${NAME}-$VERSION/debian
for f in $(find ${NAME}-$VERSION/debian -type f) ; do
  do_substs < $f > /tmp/$$.tmp && chmod --reference=$f /tmp/$$.tmp && mv /tmp/$$.tmp $f
done

pushd ${NAME}-$VERSION

dch -D $(lsb_release -cs) --newversion $VERSION-$RELEASE "Local automatic build"
debuild -uc -us -sa

fi
