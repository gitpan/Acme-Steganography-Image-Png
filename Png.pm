package Acme::Steganography::Image::Png;

use strict;
use vars qw($VERSION @ISA);

use Imager;
require Class::Accessor;
use Carp;

@ISA = qw(Class::Accessor);

$VERSION = '0.01';

my @keys = qw(offset data section x y datum_length done filename_generator
	      suffix);

# What arguments can we accept to the constructor.
# Am I reinventing the wheel here?
my %keys;
@keys{@keys} = ();

sub _keys {
  return \%keys;
}

Acme::Steganography::Image::Png->mk_accessors(@keys);

# This will get refactored out at some point to support other formats.
sub generate_header {
    my ($self) = shift;
    my $section = $self->section;

    my $header = pack 'w', $section;
    if (!$section) {
	$header .= pack 'w', length ${$self->data};
    }
    $header;
}

sub default_filename_generator {
  my $state = shift;
  $state ||= 0;
  my $new_state = $state+1;
  # really unimaginative filenames by default
  ($state, $new_state);
}

package Acme::Steganography::Image::Png::FlashingNeonSignGrey;

use vars '@ISA';
@ISA = 'Acme::Steganography::Image::Png';

# Raw data as a greyscale PNG

sub generate_next_image {
    my ($self) = shift;
    my $datum = $self->generate_header;
    my $offset = $self->offset;
    my $datum_length = $self->datum_length;
    # Fill our blob of data to the correct length
    my $grab = $datum_length - length $datum;
    $datum .= substr ${$self->data()}, $offset, $grab;
    $self->offset($offset + $grab);

    if (length $datum < $datum_length) {
      # Need to pad it. NUL is so uninspiring.
      $datum .= "\0" x ($datum_length - length $datum);
      $self->done(1);
    } elsif (length ${$self->data()} == $self->offset) {
      warn length $datum;
    }
    $self->section($self->section + 1);

    my $img = new Imager;
    $img->read(data=>$datum, type => 'raw', xsize => $self->x,
	       ysize => $self->y, datachannels=>1, storechannels=>1, bits=>8);
    $img;
}

sub calculate_datum_length {
  my $self = shift;
  $self->x * $self->y;
}

sub extract_payload {
  my ($class, $img) = @_;
  my $datum;
  $img->write(data=> \$datum, type => 'raw');
  $datum;
}

package Acme::Steganography::Image::Png;

sub new {
  my $class = shift;
  croak "Use a classname, not a reference for " . __PACKAGE__ . "::new"
    if ref $class;
  my $self = bless {}, $class;
  my %args = @_;
  my $acceptable = $self->_keys();
  foreach (keys %args) {
    croak "Unknown parameter $_" unless exists $acceptable->{$_};
    $self->set($_, $args{$_});
  }
  $self->x(352) unless $args{x};
  $self->y(288) unless $args{y};

  # Kowtow to the metadata bodging into filenames world
  $self->suffix('.png');

  $self;
}

sub type {
  'png';
}

sub write_images {
  my $self = shift;
  $self->section(0);
  $self->offset(0);
  $self->datum_length($self->calculate_datum_length());
  my $type = $self->type;
  my $filename_generator
    = $self->filename_generator || \&default_filename_generator;

  my @filenames;

  my ($filename, $state);
  while (!$self->done()) {
    my $image = $self->generate_next_image;
    ($filename, $state) = &$filename_generator($state);
    $filename .= $self->suffix;
    $image->write(file => $filename, type=> $type);
    push @filenames, $filename;
  }
  @filenames;
}

# package method
sub read_files {
  my $class = shift;
  # This is intentionally a "sparse" array to avoid some "interesting" DOS
  # possibilities.
  my $length;
  my %got;
  foreach my $file (@_) {
    my $img = new Imager;
    $img->open(file => $file) or carp "Can't read '$file': $img->errstr";
    my $payload = $class->extract_payload($img);
    my $datum;
    my $section;
    ($section, $datum) = unpack "wa*", $payload;
    if ($section == 0) {
      # Oops. Strip off the length.
      ($length, $datum) = unpack "wa*", $datum;
    }
    $got{$section} = $datum;
  }
  carp "Did not find first section in files @_" unless defined $length;

  my $data = join '', map {$got{$_}} sort {$a <=> $b} keys %got;
  substr ($data, $length) = '';

  $data;
}

1;
__END__

=head1 NAME

Acme::Steganography::Image::Png - hide data (badly) in Png images

=head1 SYNOPSIS

  use Acme::Steganography::Image::Png;

  my $writer = Acme::Steganography::Image::Png::FlashingNeonSignGrey->new();
  $writer->data(\$data); # Write your data out as greyscale PNGs
  # Returns a list of the filenams it wrote to
  my @filenames = $writer->write_images;

  # Then read it back.
  my $reread =
     Acme::Steganography::Image::Png::FlashingNeonSignGrey->read_files(@files);

=head1 DESCRIPTION

Acme::Steganography::Image::Png is extremely ineffective at hiding your
secrets inside Png images.

Currently the only implementation is
Acme::Steganography::Image::Png::FlashingNeonSignGrey which blatantly stuffs
your data into greyscale PNG files with absolutely no attempt to hide it.

Write your data out by calling C<write_images>

Read your data back in by calling C<read_files>

You don't have to return the filenames in the correct order.

=head1 BUGS

Virtually no documentation. There's the source code...

Not very many tests.

Not robust against missing files when re-reading

If you want real steganography, you're in the wrong place.

Doesn't really do enough daft stuff yet to live up to being a proper Acme
module. There are plans.

=head1 AUTHOR

Nicholas Clark <nick@talking.bollo.cx>, based on code written by JCHIN after
a conversation we had.

=cut
