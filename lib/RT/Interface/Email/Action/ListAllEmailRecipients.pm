package RT::Interface::Email::Action::ListAllEmailRecipients;

use strict;
use warnings;

use Role::Basic 'with';
with 'RT::Interface::Email::Role';

use RT::Interface::Email;

=head1 NAME

RT::Interface::Email::Action::ListAllEmailRecipeints

=head1 SYNOPSIS

This is a copy of RT's Action/Defaults.pm email plugin which is the
default handler for comment and correspond. This version adds the
call to process all email recipients and make the list available as
a template variable. Otherwise, it is the same.

=cut

sub _HandleCreate {
    my %args = (
        Subject     => undef,
        Message     => undef,
        Ticket      => undef,
        Queue       => undef,
        @_,
    );

    my $head = $args{Message}->head;

    my @Cc;
    my @Requestors = ( $args{Ticket}->CurrentUser->id );
    if (RT->Config->Get('ParseNewMessageForTicketCcs')) {
        my $user = $args{Ticket}->CurrentUser->UserObj;
        my $current_address = lc $user->EmailAddress;

        @Cc =
            grep $_ ne $current_address && !RT::EmailParser->IsRTAddress( $_ ),
            map lc $user->CanonicalizeEmailAddress( $_->address ),
            map RT::EmailParser->CleanupAddresses( Email::Address->parse(
                  Encode::decode( "UTF-8", $head->get( $_ ) ) ) ),
            qw(To Cc);
    }

    # ExtractTicketId may have been overridden, and edited the Subject
    my $subject = Encode::decode( "UTF-8", $head->get('Subject') );
    chomp $subject;

    RT::Extension::ListAllEmailRecipients::FindNotificationRecipients(
        Ticket => $args{'Ticket'},
        Queue     => $args{Queue}->Id,
        Subject   => $subject,
        Requestor => \@Requestors,
        Cc        => \@Cc,
        MIMEObj   => $args{Message},
        UpdateInterface => 'EmailCreate');

    my ( $id, $Transaction, $ErrStr ) = $args{Ticket}->Create(
        Queue     => $args{Queue}->Id,
        Subject   => $subject,
        Requestor => \@Requestors,
        Cc        => \@Cc,
        MIMEObj   => $args{Message},
    );
    return if $id;

    MailError(
        Subject     => "Ticket creation failed: $args{Subject}",
        Explanation => $ErrStr,
        FAILURE     => 1,
    );
}

sub HandleComment {
    _HandleEither( @_, Action => "Comment" );
}

sub HandleCorrespond {
    _HandleEither( @_, Action => "Correspond" );
}


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
