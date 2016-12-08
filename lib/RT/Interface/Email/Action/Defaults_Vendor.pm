package RT::Interface::Email::Action::Defaults;

use strict;
use warnings;
no warnings qw(redefine);

sub _HandleEither {
    my %args = (
        Action      => undef,
        Message     => undef,
        Subject     => undef,
        Ticket      => undef,
        TicketId    => undef,
        Queue       => undef,
        @_,
    );

    return _HandleCreate(@_) unless $args{TicketId};

    unless ( $args{Ticket}->Id ) {
        MailError(
            Subject     => "Message not recorded: $args{Subject}",
            Explanation => "Could not find a ticket with id " . $args{TicketId},
            FAILURE     => 1,
        );
    }

    RT::Extension::ListAllEmailRecipients::FindNotificationRecipients(
        @_,
        UpdateInterface => 'Email');

    my $action = ucfirst $args{Action};
    my ( $status, $msg ) = $args{Ticket}->$action( MIMEObj => $args{Message} );
    return if $status;
}

1;
