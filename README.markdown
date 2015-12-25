Arch Linux AMIs
===============
This project is a script/framework to create [Amazon Machine Image][]s (images
that act as ‘blueprints,’ or a sort of ‘server factory,’ for [Amazon’s EC2][EC2]
service) of [Arch Linux][], a particularly elegant and powerful [Linux][]
distribution.

  [Amazon Machine Image]: <http://en.wikipedia.org/wiki/Amazon_Machine_Image>
    "Wikipedia on Amazon Machine Images"
  [EC2]: <http://aws.amazon.com/ec2/>
    "Amazon’s Elastic Compute Cloud service"
  [Arch Linux]: <http://wiki.archlinux.org/index.php/Arch_Linux>
    "The Arch Linux wiki"
  [Linux]: <http://en.wikipedia.org/wiki/Linux>
    "Wikipedia on the Linux kernel"

### Arch Linux
Arch Linux, a superlatively clean and elegant distro, generally follows ‘the
[Arch Way][],’ a set of four core tenets governing the design of Arch, and its
configuration system and package repository:

- *Simple*: without unnecessary additions, modifications, or complications
- *Elegant*: combining simplicity, power, effectiveness, a quality of neatness
  and an ingenious grace of design
- *Versatile*: capable of doing many things competently; having varied uses or
  many functions
- *Expedient*: easy, or quick; convenient

  [Arch Way]: <http://wiki.archlinux.org/index.php/The_Arch_Way_v2.0>
    "The Arch wiki on the Arch Way"

### AMI design
These AMIs are designed to be extremely light, and absolutely ‘Arch-y.’ As an
example, the core ‘Nucleus’ AMI contains *exactly twenty packages*, one of
which is the filesystem, and one of which is a licenses packages that I am
legally required to distribute. That’s **nineteen**, or possibly less, pieces
of software!

In some cases, one might even say I’ve gone too far. The Nucleus doesn’t even
contain a text editor! However, I am of the opinion that servers, even more
than minimalist desktops (and virtualized servers, like those on EC2, even
moreso than normal servers, as they can be instantiated by other machines and
may possibly never even have a human being `ssh` into them, or indeed, touch
them in any way), should have absolutely no bloat, no unneeded software to
configure or daemons that may leave security holes; thus, I’m confident that
here, I’ve taken the right path.

These machines are built to take advantage of Amazon’s infrastructure
where possible; in most cases, they will utilize features like your instance’s
‘ephemeral store,’ the EC2 public keys, and the powerful EC2 firewall, to your
advantage.

Structure
---------
This system is pre-configured to build several different types of AMIs. Each
one is heavily based on the previous one, but with more functionality. They
range from the exceedingly thin to the exceedingly functional.

The planned types of AMIs are described by this tree:

- `Nucleus`: The thinnest possible system, capable only of booting, accepting
  SSH connections, and installing more packages. This is where to start if you
  don’t want *any* of the functionality provided by the fatter packages, and
  want to design yourself the lightest possible server image.
  - `Atom`: (*not yet implemented*) The basis of the rest of the system; the
    `Atom` AMIs all have a a few admin amenities (like text editors, a daemon
    monitoring/management system), as well as instantiation magic left out of
    the `Nucleus`.
    - `Web`: (*not yet implemented*)
      - `Ruby`: (*not yet implemented*)
        - `Passenger`: (*not yet implemented*)
      - `JavaScript`: (*not yet implemented*)
    - `git`: (*not yet implemented*)
    - `Bundling`: (*not yet implemented*)

**Note:** The `Nucleus` AMI *does not have* the instantiation magic provided
by the rest of the systems; you will have to configure your user accounts,
yourself, from the `root` user account, your mirrors will not be ranked at
boot, and so on. Everything is left up to you.

Usage
-----
The easiest way to use these AMIs is to instantiate one from the list of AMIs
that I (elliottcable) have already built and registered. I won’t keep a list
here yet; once I release stable AMIs, I may add them to this README. In the
mean time, you can get a complete list of AMIs I have release with the
following command:

    ec2-describe-images --show-empty-fields \
      --owner "316177411691" --executable-by all | less -S

#### Building your own copies of the AMIs
I **suggest**, however, that, instead of using *my* AMIs, you simply build
your own using this script; in general, you never know what an AMI published
by somebody else contains. If you run this script yourself, after reading it,
you can have a much more particular understanding of what, exactly, is in the
machine that you’re running.

Not that that covers *all* of your bases; for instance, this script utilizes
a ‘bundling host,’ and if that host was compromised, anything could
theoretically be injected into your new AMIs… but it’s still generally a more
intelligent course of action.

To get more information about building your own AMIs using this system, run
`bundle.sh` without any arguments:

    ./bundle.sh

### Building customized AMIs
This system is designed to be extremely flexible; there is really no reason
for you to use the pre-built AMIs, or even run the script as-is; you can
easily customize the script to build AMIs that exactly match your needs,
either by creating new preparation scripts, or re-bundling the AMIs produced
by this script. You could even use a combination of both techniques to produce
a tree structure of personalized AMIs for various purposes; that aligns quite
well with the intended usage scenario of EC2, after all.

#### Custom preparation scripts
The `bundle.sh` script, in this directory, is the core of the system; it
builds and configures bundle host and kernel host machines, and is also
responsible for testing built AMIs against kernels in various availability
zones.

After a bundle host is prepared, and the kernel host is done with, execution
is passed (on the bundling host) to preparation scripts (in the `InstanceType`
folder, i.e. `InstanceType/bundle.sh`). These are entirely responsible for
actually installing and configuring all software to be packaged into the new
AMI. You can, therefore, write your own such scripts, to set up your AMI
however you desire.

#### Re-bundling
I, personally, don’t generally re-bundle AMIs; I prefer to know exactly what’s
going on, which is achieved by building them myself from scratch. However,
it’s not a difficult task.

There is plenty of information on re-bundling AMIs in the [EC2 docs][];
[alestic][] also has [tutorial][] on the subject. The AMIs created by this
project are friendly to re-bundling; however, be aware that you need to clean
out some files created, that inform the instance of its state (such as
whether or not it has been instantiated yet; this is how these AMIs preform
first-boot initialization when instantiated). This is fairly easy, simply run
the following command:

    rm -f /usr/aws/ec2/.*

This will clear out any files created by the hosts on boot, which will allow
your bundled system to be initialized properly every time it is subsequently
instantiated.

  [EC2 documentation]: <http://docs.amazonwebservices.com/AWSEC2/latest/DeveloperGuide/index.html?ami-from-existing-image.html>
    "Re-bundling instructions from EC2’s Developer Guide"
  [alestic]: <http://alestic.com/blog/>
    "An interesting blog on EC2"
  [tutorial]: <http://alestic.com/2009/06/ec2-ami-bundle>
    "alestic’s re-bundling tutorial"

License
-------
This project is released for public usage under the terms of the very-permissive [ISC license][] (a
modern evolution of the MIT / BSD licenses); more information is available in [COPYING][].

   [ISC license]: <http://choosealicense.com/licenses/isc/> "Information about the ISC license"
   [COPYING]: <./COPYING.text>
