%global _hardened_build 1
%define _build_id_links none
%define debug_package %{nil}

%global app_version %{?app_version}%{!?app_version:1.2.10}
%global app_release %{?app_release}%{!?app_release:1}

Name:           wifiman-desktop
Version:        %{app_version}
Release:        %{app_release}%{?dist}
Summary:        Discover devices and access Teleport VPNs
License:        MIT
Vendor:         Ubiquiti Inc. <monitoring@wifiman.com>
URL:            https://wifiman.com/
Source0:        %{name}-%{version}-stage.tar.gz
Source1:        LICENSE
Source2:        wifiman-desktop-launcher.sh
Source3:        default-service.json
Source4:        wifiman-desktopd-wrapper.sh
Source5:        wifiman-desktop.desktop

BuildArch:      x86_64
BuildRequires:  desktop-file-utils
BuildRequires:  systemd-rpm-macros

Requires:       gtk3
Requires:       libX11
Requires:       libXcomposite
Requires:       libXcursor
Requires:       libXdamage
Requires:       libXext
Requires:       libXfixes
Requires:       libXi
Requires:       libXrandr
Requires:       libXtst
Requires:       mesa-libgbm
Requires:       libglvnd-egl
Requires:       nss
Requires:       nspr
Requires:       at-spi2-core
Requires:       pango
Requires:       cairo
Requires:       gdk-pixbuf2
Requires:       systemd
Requires:       wireguard-tools
Requires:       dbus-x11

%description
WiFiman Desktop packaged for newer Fedora releases using an app-private
compatibility runtime for the older WebKitGTK 4.0 / libsoup2 stack that the
upstream 1.2.x binary still requires.

%prep
%autosetup -c -T
mkdir -p staged
cd staged
%{__tar} -xzf %{SOURCE0}

%build

%install
rm -rf %{buildroot}

UPSTREAM_BIN=
for candidate in staged/upstream/usr/bin/wi-fiman-desktop staged/upstream/usr/bin/wifiman-desktop; do
  if [ -f "$candidate" ]; then
    UPSTREAM_BIN="$candidate"
    break
  fi
done
[ -n "$UPSTREAM_BIN" ]

UPSTREAM_LIBDIR=
for candidate in staged/upstream/usr/lib/wi-fiman-desktop staged/upstream/usr/lib/wifiman-desktop; do
  if [ -d "$candidate" ]; then
    UPSTREAM_LIBDIR="$candidate"
    break
  fi
done
[ -n "$UPSTREAM_LIBDIR" ]

UPSTREAM_ICON_32=
for candidate in staged/upstream/usr/share/icons/hicolor/32x32/apps/wi-fiman-desktop.png staged/upstream/usr/share/icons/hicolor/32x32/apps/wifiman-desktop.png; do
  if [ -f "$candidate" ]; then
    UPSTREAM_ICON_32="$candidate"
    break
  fi
done
[ -n "$UPSTREAM_ICON_32" ]

UPSTREAM_ICON_128=
for candidate in staged/upstream/usr/share/icons/hicolor/128x128/apps/wi-fiman-desktop.png staged/upstream/usr/share/icons/hicolor/128x128/apps/wifiman-desktop.png; do
  if [ -f "$candidate" ]; then
    UPSTREAM_ICON_128="$candidate"
    break
  fi
done
[ -n "$UPSTREAM_ICON_128" ]

UPSTREAM_ICON_256=
for candidate in staged/upstream/usr/share/icons/hicolor/256x256@2/apps/wi-fiman-desktop.png staged/upstream/usr/share/icons/hicolor/256x256@2/apps/wifiman-desktop.png; do
  if [ -f "$candidate" ]; then
    UPSTREAM_ICON_256="$candidate"
    break
  fi
done
[ -n "$UPSTREAM_ICON_256" ]

install -d %{buildroot}%{_prefix}/lib/wi-fiman-desktop
install -m 0755 "$UPSTREAM_BIN" \
  %{buildroot}%{_prefix}/lib/wi-fiman-desktop/wi-fiman-desktop-bin
cp -a "$UPSTREAM_LIBDIR"/. %{buildroot}%{_prefix}/lib/wi-fiman-desktop/

install -d %{buildroot}%{_localstatedir}/lib/%{name}
install -m 0644 %{SOURCE3} %{buildroot}%{_localstatedir}/lib/%{name}/service.json
touch %{buildroot}%{_localstatedir}/lib/%{name}/wifiman-desktop.log
rm -f %{buildroot}%{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.log
ln -sfn %{_localstatedir}/lib/%{name}/wifiman-desktop.log %{buildroot}%{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.log

install -d %{buildroot}%{_prefix}/lib/wi-fiman-desktop/compat
cp -a staged/compat/lib64 %{buildroot}%{_prefix}/lib/wi-fiman-desktop/compat/
cp -a staged/compat/libexec %{buildroot}%{_prefix}/lib/wi-fiman-desktop/compat/

install -d %{buildroot}%{_libexecdir}/webkit2gtk-4.0
install -m 0755 staged/compat/libexec/webkit2gtk-4.0/WebKitNetworkProcess \
  %{buildroot}%{_libexecdir}/webkit2gtk-4.0/WebKitNetworkProcess
install -m 0755 staged/compat/libexec/webkit2gtk-4.0/WebKitWebProcess \
  %{buildroot}%{_libexecdir}/webkit2gtk-4.0/WebKitWebProcess
install -d %{buildroot}%{_libdir}/webkit2gtk-4.0/injected-bundle
install -m 0644 staged/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so \
  %{buildroot}%{_libdir}/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so

install -d %{buildroot}%{_bindir}
install -m 0755 %{SOURCE2} %{buildroot}%{_bindir}/wifiman-desktop
install -m 0755 %{SOURCE4} %{buildroot}%{_prefix}/lib/wi-fiman-desktop/wifiman-desktopd-wrapper

install -d %{buildroot}%{_unitdir}
install -m 0644 "$UPSTREAM_LIBDIR"/wifiman-desktop.service \
  %{buildroot}%{_unitdir}/%{name}.service
sed -i 's#^ExecStart=.*#ExecStart=/usr/lib/wi-fiman-desktop/wifiman-desktopd-wrapper#' \
  %{buildroot}%{_unitdir}/%{name}.service

install -d %{buildroot}%{_datadir}/applications
install -m 0644 %{SOURCE5} \
  %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop

install -d %{buildroot}%{_datadir}/icons/hicolor/32x32/apps
install -m 0644 "$UPSTREAM_ICON_32" \
  %{buildroot}%{_datadir}/icons/hicolor/32x32/apps/wifiman-desktop.png
install -d %{buildroot}%{_datadir}/icons/hicolor/128x128/apps
install -m 0644 "$UPSTREAM_ICON_128" \
  %{buildroot}%{_datadir}/icons/hicolor/128x128/apps/wifiman-desktop.png
install -d %{buildroot}%{_datadir}/icons/hicolor/256x256@2/apps
install -m 0644 "$UPSTREAM_ICON_256" \
  %{buildroot}%{_datadir}/icons/hicolor/256x256@2/apps/wifiman-desktop.png

install -d %{buildroot}%{_datadir}/licenses/%{name}
install -m 0644 %{SOURCE1} %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop
grep -qx 'Name=WiFiman Desktop' %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop
grep -qx 'Exec=wifiman-desktop %U' %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop
grep -qx 'Icon=wifiman-desktop' %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop

%post
%systemd_post %{name}.service
/bin/touch --no-create %{_datadir}/icons/hicolor &>/dev/null || :
update-desktop-database %{_datadir}/applications &>/dev/null || :
update-mime-database %{_datadir}/mime &>/dev/null || :

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun_with_restart %{name}.service
if [ $1 -eq 0 ] ; then
    /bin/touch --no-create %{_datadir}/icons/hicolor &>/dev/null || :
    /usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || :
fi

%posttrans
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || :

%files
%license %{_datadir}/licenses/%{name}/LICENSE
%{_bindir}/wifiman-desktop
%{_unitdir}/%{name}.service
%{_datadir}/applications/wifiman-desktop.desktop
%{_datadir}/icons/hicolor/32x32/apps/wifiman-desktop.png
%{_datadir}/icons/hicolor/128x128/apps/wifiman-desktop.png
%{_datadir}/icons/hicolor/256x256@2/apps/wifiman-desktop.png
%dir %{_prefix}/lib/wi-fiman-desktop
%{_prefix}/lib/wi-fiman-desktop/wi-fiman-desktop-bin
%{_prefix}/lib/wi-fiman-desktop/.env
%{_prefix}/lib/wi-fiman-desktop/.env.development
%{_prefix}/lib/wi-fiman-desktop/.env.staging
%{_prefix}/lib/wi-fiman-desktop/wg
%{_prefix}/lib/wi-fiman-desktop/wg-quick
%{_prefix}/lib/wi-fiman-desktop/wg_report.sh
%{_prefix}/lib/wi-fiman-desktop/wifiman-desktopd
%{_prefix}/lib/wi-fiman-desktop/wifiman-desktopd-wrapper
%{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.service
%{_prefix}/lib/wi-fiman-desktop/wireguard-go
%dir %{_localstatedir}/lib/%{name}
%config(noreplace) %{_localstatedir}/lib/%{name}/service.json
%ghost %config(noreplace) %{_localstatedir}/lib/%{name}/wifiman-desktop.log
%{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.log
%dir %{_prefix}/lib/wi-fiman-desktop/compat
%{_prefix}/lib/wi-fiman-desktop/compat/lib64/*
%{_prefix}/lib/wi-fiman-desktop/compat/libexec/webkit2gtk-4.0/WebKitNetworkProcess
%{_prefix}/lib/wi-fiman-desktop/compat/libexec/webkit2gtk-4.0/WebKitWebProcess
%dir %{_libexecdir}/webkit2gtk-4.0
%{_libexecdir}/webkit2gtk-4.0/WebKitNetworkProcess
%{_libexecdir}/webkit2gtk-4.0/WebKitWebProcess
%dir %{_libdir}/webkit2gtk-4.0
%dir %{_libdir}/webkit2gtk-4.0/injected-bundle
%{_libdir}/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so

%changelog
* Mon Apr 27 2026 F.R.I.D.A.Y. <265173460+mk-friday@users.noreply.github.com> 1.2.10-1
- add bundled SELinux policy source/installer workflow for daemon networking and runtime state
- move mutable runtime state and seeded service.json into /var/lib/wifiman-desktop
- remove duplicate upstream desktop/icon names after share copy and package wg_report.sh
- tolerate upstream wi-fiman/wifiman path and icon renames in staging and RPM install
- rename staging script to versionless name
- suppress upstream in-app updater prompt in RPM packaging
- retarget packaging flow to upstream 1.2.10

* Sat Apr 25 2026 Friday <friday@local> 1.1.2-1
- rework packaging around staged upstream 1.1.2 layout
- bundle private compat runtime for newer Fedora releases
- install wrapper, desktop file, icons, and systemd unit from staged tree
