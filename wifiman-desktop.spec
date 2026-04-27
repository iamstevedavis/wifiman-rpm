%global _hardened_build 1
%define _build_id_links none
%define debug_package %{nil}

Name:           wifiman-desktop
Version:        1.1.2
Release:        1%{?dist}
Summary:        Discover devices and access Teleport VPNs
License:        MIT
Vendor:         Ubiquiti Inc. <monitoring@wifiman.com>
URL:            https://wifiman.com/
Source0:        %{name}-%{version}-stage.tar.gz
Source1:        LICENSE
Source2:        wi-fiman-desktop-launcher.sh

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
upstream 1.1.x binary still requires.

%prep
%autosetup -c -T
mkdir -p staged
cd staged
%{__tar} -xzf %{SOURCE0}

%build

%install
rm -rf %{buildroot}

install -d %{buildroot}%{_prefix}/lib/wi-fiman-desktop
install -m 0755 staged/upstream/usr/bin/wi-fiman-desktop \
  %{buildroot}%{_prefix}/lib/wi-fiman-desktop/wi-fiman-desktop-bin
cp -a staged/upstream/usr/lib/wi-fiman-desktop/. %{buildroot}%{_prefix}/lib/wi-fiman-desktop/
cp -a staged/upstream/usr/share %{buildroot}%{_prefix}/

install -d %{buildroot}%{_prefix}/lib/wi-fiman-desktop/compat
cp -a staged/compat/lib64 %{buildroot}%{_prefix}/lib/wi-fiman-desktop/compat/
cp -a staged/compat/libexec %{buildroot}%{_prefix}/lib/wi-fiman-desktop/compat/

install -d %{buildroot}%{_bindir}
install -m 0755 %{SOURCE2} %{buildroot}%{_bindir}/wi-fiman-desktop

install -d %{buildroot}%{_unitdir}
install -m 0644 staged/upstream/usr/lib/wi-fiman-desktop/wifiman-desktop.service \
  %{buildroot}%{_unitdir}/%{name}.service

install -d %{buildroot}%{_datadir}/applications
install -m 0644 staged/upstream/usr/share/applications/wi-fiman-desktop.desktop \
  %{buildroot}%{_datadir}/applications/wi-fiman-desktop.desktop
sed -i 's/^Comment=.*/Comment=Discover devices and access Teleport VPNs/' \
  %{buildroot}%{_datadir}/applications/wi-fiman-desktop.desktop

install -d %{buildroot}%{_datadir}/icons/hicolor/32x32/apps
install -m 0644 staged/upstream/usr/share/icons/hicolor/32x32/apps/wi-fiman-desktop.png \
  %{buildroot}%{_datadir}/icons/hicolor/32x32/apps/wi-fiman-desktop.png
install -d %{buildroot}%{_datadir}/icons/hicolor/128x128/apps
install -m 0644 staged/upstream/usr/share/icons/hicolor/128x128/apps/wi-fiman-desktop.png \
  %{buildroot}%{_datadir}/icons/hicolor/128x128/apps/wi-fiman-desktop.png
install -d %{buildroot}%{_datadir}/icons/hicolor/256x256@2/apps
install -m 0644 staged/upstream/usr/share/icons/hicolor/256x256@2/apps/wi-fiman-desktop.png \
  %{buildroot}%{_datadir}/icons/hicolor/256x256@2/apps/wi-fiman-desktop.png

install -d %{buildroot}%{_datadir}/licenses/%{name}
install -m 0644 %{SOURCE1} %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/wi-fiman-desktop.desktop

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
%{_bindir}/wi-fiman-desktop
%{_unitdir}/%{name}.service
%{_datadir}/applications/wi-fiman-desktop.desktop
%{_datadir}/icons/hicolor/32x32/apps/wi-fiman-desktop.png
%{_datadir}/icons/hicolor/128x128/apps/wi-fiman-desktop.png
%{_datadir}/icons/hicolor/256x256@2/apps/wi-fiman-desktop.png
%dir %{_prefix}/lib/wi-fiman-desktop
%{_prefix}/lib/wi-fiman-desktop/wi-fiman-desktop-bin
%{_prefix}/lib/wi-fiman-desktop/.env
%{_prefix}/lib/wi-fiman-desktop/.env.development
%{_prefix}/lib/wi-fiman-desktop/.env.staging
%{_prefix}/lib/wi-fiman-desktop/wg
%{_prefix}/lib/wi-fiman-desktop/wg-quick
%{_prefix}/lib/wi-fiman-desktop/wifiman-desktopd
%{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.service
%{_prefix}/lib/wi-fiman-desktop/wireguard-go
%dir %{_prefix}/lib/wi-fiman-desktop/compat
%{_prefix}/lib/wi-fiman-desktop/compat/lib64/*
%{_prefix}/lib/wi-fiman-desktop/compat/libexec/webkit2gtk-4.0/WebKitNetworkProcess
%{_prefix}/lib/wi-fiman-desktop/compat/libexec/webkit2gtk-4.0/WebKitWebProcess

%changelog
* Sat Apr 25 2026 Friday <friday@local> 1.1.2-1
- rework packaging around staged upstream 1.1.2 layout
- bundle private compat runtime for newer Fedora releases
- install wrapper, desktop file, icons, and systemd unit from staged tree
