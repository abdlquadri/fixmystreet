package FixMyStreet::SendReport::EmptyHomes;

use Moose;
use namespace::autoclean;
use Data::Printer;

BEGIN { extends 'FixMyStreet::SendReport::Email'; }

has 'councils' => (is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'to' => (is => 'rw', isa => 'ArrayRef', default => sub { [] } );

my %councils = ();
my @to;

sub reset {
    my $self = shift;

    $self->councils( {} );
    $self->to( [] );
}

sub add_council {
    my $self = shift;
    my $council = shift;
    my $name = shift;

    $self->councils->{ $council } = $name;
}

sub build_recipient_list {
    my $self = shift;
    my $row = shift;
    my $areas_info = shift;
    my %recips;

    my $all_confirmed = 1;
    foreach my $council ( keys %{ $self->councils } ) {
        my $contact = FixMyStreet::App->model("DB::Contact")->find( {
            deleted => 0,
            area_id => $council,
            category => 'Empty property',
        } );

        my ($council_email, $confirmed, $note) = ( $contact->email, $contact->confirmed, $contact->note );

        $council_email = essex_contact($row->latitude, $row->longitude) if $council == 2225;
        $council_email = oxfordshire_contact($row->latitude, $row->longitude) if $council == 2237 && $council_email eq 'SPECIAL';

        unless ($confirmed) {
            $all_confirmed = 0;
            #$note = 'Council ' . $row->council . ' deleted'
                #unless $note;
            $council_email = 'N/A' unless $council_email;
            #$notgot{$council_email}{$row->category}++;
            #$note{$council_email}{$row->category} = $note;
        }

        push @{ $self->to }, [ $council_email, $self->councils->{ $council } ];
        $recips{$council_email} = 1;

        my $country = $areas_info->{$council}->{country};
        if ($country eq 'W') {
            $recips{ 'shelter@' . mySociety::Config::get('EMAIL_DOMAIN') } = 1;
        } else {
            $recips{ 'eha@' . mySociety::Config::get('EMAIL_DOMAIN') } = 1;
        }
    }

    return () unless $all_confirmed;
    return keys %recips;
}

sub send {
    my $self = shift;
    my ( $row, $h, $to, $template, $recips, $nomail, $areas_info ) = @_;

    my @recips;

    # on a staging server send emails to ourselves rather than the councils
    if (mySociety::Config::get('STAGING_SITE')) {
        @recips = ( mySociety::Config::get('CONTACT_EMAIL') );
    } else {
        @recips = $self->build_recipient_list( $row, $areas_info );
    }


    return unless @recips;

    my $result = FixMyStreet::App->send_email_cron(
        {
            _template_ => $template,
            _parameters_ => $h,
            To => $self->to,
            From => [ $row->user->email, $row->name ],
        },
        mySociety::Config::get('CONTACT_EMAIL'),
        \@recips,
        $nomail
    );

    return $result;
}

# Essex has different contact addresses depending upon the district
# Might be easier if we start storing in the db all areas covered by a point
# Will do for now :)
sub essex_contact {
    my $district = _get_district_for_contact(@_);
    my $email;
    $email = 'eastarea' if $district == 2315 || $district == 2312;
    $email = 'midarea' if $district == 2317 || $district == 2314 || $district == 2316;
    $email = 'southarea' if $district == 2319 || $district == 2320 || $district == 2310;
    $email = 'westarea' if $district == 2309 || $district == 2311 || $district == 2318 || $district == 2313;
    die "Returned district $district which is not in Essex!" unless $email;
    return "highways.$email\@essexcc.gov.uk";
}

# Oxfordshire has different contact addresses depending upon the district
sub oxfordshire_contact {
    my $district = _get_district_for_contact(@_);
    my $email;
    $email = 'northernarea' if $district == 2419 || $district == 2420 || $district == 2421;
    $email = 'southernarea' if $district == 2417 || $district == 2418;
    die "Returned district $district which is not in Oxfordshire!" unless $email;
    return "$email\@oxfordshire.gov.uk";
}

sub _get_district_for_contact {
    my ( $lat, $lon ) = @_;
    my $district =
      mySociety::MaPit::call( 'point', "4326/$lon,$lat", type => 'DIS' );
    ($district) = keys %$district;
    return $district;
}
1;
