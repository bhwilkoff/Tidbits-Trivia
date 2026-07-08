using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Networking;
using Xunit;

/// The join-wrap "add the people you played with" wiring — the VM adds a captured
/// co-player to the shared FriendStore and reflects membership.
public class CoplayerAddTest
{
    [Fact]
    public void Add_friend_persists_via_the_shared_store()
    {
        var vm = new LivePlayerViewModel();
        var uid = $"coplayer-{System.Guid.NewGuid():N}";
        var friend = new PlayerIdentity.Friend { Uid = uid, Name = "Trivia Tina" };
        try
        {
            Assert.False(vm.IsFriend(uid));
            vm.AddFriend(friend);
            Assert.True(vm.IsFriend(uid));                             // reflected on the VM
            Assert.True(GameData.Shared.Value.Friends.Contains(uid));  // and in the store
        }
        finally { GameData.Shared.Value.Friends.Remove(uid); }
    }
}
