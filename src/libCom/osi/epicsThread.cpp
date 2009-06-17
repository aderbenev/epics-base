/*************************************************************************\
* Copyright (c) 2008 UChicago Argonne LLC, as Operator of Argonne
*     National Laboratory.
* Copyright (c) 2002 The Regents of the University of California, as
*     Operator of Los Alamos National Laboratory.
* EPICS BASE is distributed subject to a Software License Agreement found
* in file LICENSE that is included with this distribution. 
\*************************************************************************/
//
// epicsThread.cpp,v 1.16.2.23 2008/10/08 22:44:32 anj Exp
//
// Author: Jeff Hill
//

#include <exception>
#include <typeinfo>

#include <stdio.h>
#include <stddef.h>
#include <float.h>

#define epicsExportSharedSymbols
#include "epicsAlgorithm.h"
#include "epicsTime.h"
#include "epicsThread.h"
#include "epicsAssert.h"
#include "epicsGuard.h"
#include "errlog.h"

epicsThreadRunable::~epicsThreadRunable () {}
void epicsThreadRunable::run () {}
void epicsThreadRunable::show ( unsigned int ) const {}

extern "C" void epicsThreadCallEntryPoint ( void * pPvt )
{
    epicsThread * pThread = 
        static_cast <epicsThread *> ( pPvt );
    bool waitRelease = false;
    try {
        pThread->pWaitReleaseFlag = & waitRelease;
        if ( pThread->beginWait () ) {
            pThread->runable.run ();
            // current thread may have run the destructor 
            // so must not touch the this pointer from
            // here on down if waitRelease is true
        }
    }
    catch ( const epicsThread::exitException & ) {
    }
    catch ( std::exception & except ) {
        if ( ! waitRelease ) {
            epicsTime cur = epicsTime::getCurrent ();
            char date[64];
            cur.strftime ( date, sizeof ( date ), "%a %b %d %Y %H:%M:%S.%f");
            char name [128];
            epicsThreadGetName ( pThread->id, name, sizeof ( name ) );
            errlogPrintf ( 
                "epicsThread: Unexpected C++ exception \"%s\" with type \"%s\" in thread \"%s\" at %s\n",
                except.what (), typeid ( except ).name (), name, date );
            // this should behave as the C++ implementation intends when an 
            // exception isnt handled. If users dont like this behavior, they 
            // can install an application specific unexpected handler.
            std::unexpected (); 
        }
    }
    catch ( ... ) {
        if ( ! waitRelease ) {
            epicsTime cur = epicsTime::getCurrent ();
            char date[64];
            cur.strftime ( date, sizeof ( date ), "%a %b %d %Y %H:%M:%S.%f");
            char name [128];
            epicsThreadGetName ( pThread->id, name, sizeof ( name ) );
            errlogPrintf ( 
                "epicsThread: Unknown C++ exception in thread \"%s\" at %s\n",
                name, date );
            errlogFlush ();
        }
        // The Linux NPTL library requires us to re-throw here; it uses
        // an untyped exception object to shut down threads when we call
        // pthread_cancel() in the os/posix/osdThread.c myAtExit()
        // handler, and aborts with "FATAL: exception not rethrown" if
        // we don't re-throw it.  This solution is incomplete though...
        throw;
    }
    if ( ! waitRelease ) {
        epicsGuard < epicsMutex > guard ( pThread->mutex );
        pThread->terminated = true;
        pThread->exitEvent.signal ();
        // once the terminated flag is set and we release the lock
        // then the "this" pointer must not be touched again
    }
}

bool epicsThread::beginWait () throw ()
{
    epicsGuard < epicsMutex > guard ( this->mutex );
    while ( ! this->begin && ! this->cancel ) {
        epicsGuardRelease < epicsMutex > unguard ( guard );
        this->event.wait ();
    }
    return this->begin && ! this->cancel;
}

void epicsThread::exit ()
{
    throw exitException ();
}

void epicsThread::exitWait () throw ()
{
    assert ( this->exitWait ( DBL_MAX ) );
}

bool epicsThread::exitWait ( const double delay ) throw ()
{
    try {
        // if destructor is running in managed thread then of 
        // course we will not wait for the managed thread to 
        // exit
        if ( this->isCurrentThread() ) {
            if ( this->pWaitReleaseFlag ) {
                *this->pWaitReleaseFlag = true;
            }
            return true;
        }
        epicsTime exitWaitBegin = epicsTime::getCurrent ();
        double exitWaitElapsed = 0.0;
        epicsGuard < epicsMutex > guard ( this->mutex );
        this->cancel = true;
        while ( ! this->terminated && exitWaitElapsed < delay ) {
            epicsGuardRelease < epicsMutex > unguard ( guard );
            this->event.signal ();
            this->exitEvent.wait ( delay - exitWaitElapsed );
            epicsTime current = epicsTime::getCurrent ();
            exitWaitElapsed = current - exitWaitBegin;
        }
    }
    catch ( std :: exception & except ) {
        errlogPrintf ( 
            "epicsThread::exitWait(): Unexpected exception "
            " \"%s\"\n", 
            except.what () );
        epicsThreadSleep ( epicsMin ( delay, 5.0 ) );
    }
    catch ( ... ) {
        errlogPrintf ( 
            "Non-standard unexpected exception in "
            "epicsThread::exitWait()\n" );
        epicsThreadSleep ( epicsMin ( delay, 5.0 ) );
    }
    return this->terminated;
}

epicsThread::epicsThread ( 
    epicsThreadRunable & runableIn, const char * pName,
        unsigned stackSize, unsigned priority ) :
    runable ( runableIn ), id ( 0 ), pWaitReleaseFlag ( 0 ),
    begin ( false ), cancel ( false ), terminated ( false )
{
    this->id = epicsThreadCreate ( 
        pName, priority, stackSize, epicsThreadCallEntryPoint, 
        static_cast < void * > ( this ) );
    if ( ! this->id ) {
        throw unableToCreateThread ();
    }
}

epicsThread::~epicsThread () throw ()
{
    while ( ! this->exitWait ( 10.0 )  ) {
        char nameBuf [256];
        this->getName ( nameBuf, sizeof ( nameBuf ) );
        fprintf ( stderr, 
            "epicsThread::~epicsThread(): "
            "blocking for thread \"%s\" to exit\n", 
            nameBuf );
        fprintf ( stderr, 
            "was epicsThread object destroyed before thread exit ?\n");
    }
}

void epicsThread::start () throw ()
{
    {
        epicsGuard < epicsMutex > guard ( this->mutex );
        this->begin = true;
    }
    this->event.signal ();
}

bool epicsThread::isCurrentThread () const throw ()
{
    return ( epicsThreadGetIdSelf () == this->id );
}

void epicsThread::resume () throw ()
{
    epicsThreadResume ( this->id );
}

void epicsThread::getName ( char *name, size_t size ) const throw ()
{
    epicsThreadGetName ( this->id, name, size );
}

epicsThreadId epicsThread::getId () const throw ()
{
    return this->id;
}

unsigned int epicsThread::getPriority () const throw ()
{
    return epicsThreadGetPriority (this->id);
}

void epicsThread::setPriority (unsigned int priority) throw ()
{
    epicsThreadSetPriority (this->id, priority);
}

bool epicsThread::priorityIsEqual (const epicsThread &otherThread) const throw ()
{
    if ( epicsThreadIsEqual (this->id, otherThread.id) ) {
        return true;
    }
    return false;
}

bool epicsThread::isSuspended () const throw ()
{
    if ( epicsThreadIsSuspended (this->id) ) {
        return true;
    }
    return false;
}

bool epicsThread::operator == (const epicsThread &rhs) const throw ()
{
    return (this->id == rhs.id);
}

void epicsThread::suspendSelf () throw ()
{
    epicsThreadSuspendSelf ();
}

void epicsThread::sleep (double seconds) throw ()
{
    epicsThreadSleep (seconds);
}

//epicsThread & epicsThread::getSelf ()
//{
//    return * static_cast<epicsThread *> ( epicsThreadGetIdSelf () );
//}

const char *epicsThread::getNameSelf () throw ()
{
    return epicsThreadGetNameSelf ();
}

bool epicsThread::isOkToBlock () throw ()
{
    return epicsThreadIsOkToBlock() != 0;
}

void epicsThread::setOkToBlock(bool isOkToBlock) throw ()
{
    epicsThreadSetOkToBlock(static_cast<int>(isOkToBlock));
}

void epicsThreadPrivateBase::throwUnableToCreateThreadPrivate ()
{
    throw epicsThreadPrivateBase::unableToCreateThreadPrivate ();
}

extern "C" {
    static epicsThreadOnceId okToBlockOnce = EPICS_THREAD_ONCE_INIT;
    epicsThreadPrivateId okToBlockPrivate;
    static const int okToBlockNo = 0;
    static const int okToBlockYes = 1;
    
    static void epicsThreadOnceIdInit(void *)
    {
        okToBlockPrivate = epicsThreadPrivateCreate();
    }
    
    int epicsShareAPI epicsThreadIsOkToBlock(void)
    {
        const int *pokToBlock;
        epicsThreadOnce(&okToBlockOnce, epicsThreadOnceIdInit, NULL);
        pokToBlock = (int *) epicsThreadPrivateGet(okToBlockPrivate);
        return (pokToBlock ? *pokToBlock : 0);
    }
    
    void epicsShareAPI epicsThreadSetOkToBlock(int isOkToBlock)
    {
        const int *pokToBlock;
        epicsThreadOnce(&okToBlockOnce, epicsThreadOnceIdInit, NULL);
        pokToBlock = (isOkToBlock) ? &okToBlockYes : &okToBlockNo;
        epicsThreadPrivateSet(okToBlockPrivate, (void *)pokToBlock);
    }
    
    epicsThreadId epicsShareAPI epicsThreadMustCreate (
        const char *name, unsigned int priority, unsigned int stackSize,
        EPICSTHREADFUNC funptr,void *parm) 
    {
        epicsThreadId id = epicsThreadCreate ( 
            name, priority, stackSize, funptr, parm );
        assert ( id );
        return id;
    }
} // extern "C"

// Ensure the main thread gets a unique ID
epicsThreadId epicsThreadMainId = epicsThreadGetIdSelf();
